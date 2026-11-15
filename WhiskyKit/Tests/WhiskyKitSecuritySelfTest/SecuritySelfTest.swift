//
//  SecuritySelfTest.swift
//  WhiskyKitSecuritySelfTest
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import CryptoKit
import Foundation
import SemanticVersion
@testable import WhiskyKit

@main
struct SecuritySelfTest {
    static func main() async {
        var failures = 0

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() {
                print("PASS: \(message)")
            } else {
                failures += 1
                print("FAIL: \(message)")
            }
        }

        check(generatedCommandQuotesArguments(), "program arguments are shell-quoted")
        check(appleScriptQuotingEscapesMetacharacters(), "AppleScript strings escape quotes and backslashes")
        check(sha256KnownValue(), "runtime SHA-256 matches a known value")
        check(manifestSignatureVerifies(), "manifest Ed25519 signature verifies and tamper fails")
        check(runtimePresenceRejectsSymlink(), "a symlinked runtime is not treated as installed")
        check(installVerifierRejectsBadChecksum(), "the installer rejects a bad archive hash")

        let longLineBytes = await streamedNoNewlineBytes()
        check(longLineBytes == 2_000_000, "long lines are chunked and preserved: \(longLineBytes)")
        check(bitmapRejectsBadDimensions(), "a bitmap with huge/negative dimensions is rejected")
        check(shortcutSizeCap(), "an oversized shortcut file is rejected")

        if failures > 0 {
            print("\(failures) security self-test(s) failed")
            exit(1)
        }
        print("All security self-tests passed")
    }

    static func generatedCommandQuotesArguments() -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "whisky-security-args-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let bottle = Bottle(bottleUrl: root)
            let command = Wine.generateRunCommand(
                at: URL(filePath: "/tmp/My Game.exe"),
                bottle: bottle,
                args: "; touch /tmp/pwned",
                environment: [:]
            )
            return command.contains("';' 'touch' '/tmp/pwned'")
                && !command.contains("; touch /tmp/pwned")
        } catch {
            print("args test error: \(error)")
            return false
        }
    }

    static func appleScriptQuotingEscapesMetacharacters() -> Bool {
        let input = "a\"b\\c"
        let expected = "a\\\"b\\\\c"
        return input.appleScriptQuoted == expected
    }

    static func sha256KnownValue() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-sha-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try Data("hello".utf8).write(to: url)
            return WhiskyWineInstaller.sha256(ofFileAt: url)
                == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        } catch {
            print("sha test error: \(error)")
            return false
        }
    }

    static func manifestSignatureVerifies() -> Bool {
        do {
            let key = Curve25519.Signing.PrivateKey()
            var manifest = WhiskyWineVersion(
                version: SemanticVersion(1, 2, 3),
                sha256: "abc",
                signature: nil
            )
            let payload = Data(manifest.signingPayload.utf8)
            manifest.signature = try key.signature(for: payload).base64EncodedString()
            let publicKey = key.publicKey.rawRepresentation.base64EncodedString()

            let valid = WhiskyWineInstaller.verifySignature(
                base64: manifest.signature ?? "",
                payload: payload,
                publicKeyBase64: publicKey
            )
            let tampered = WhiskyWineInstaller.verifySignature(
                base64: manifest.signature ?? "",
                payload: Data("other".utf8),
                publicKeyBase64: publicKey
            )
            return valid && !tampered
        } catch {
            print("signature test error: \(error)")
            return false
        }
    }

    static func runtimePresenceRejectsSymlink() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-runtime-symlink-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            let libraries = root.appending(path: "Libraries")
            let wine64 = libraries.appending(path: "Wine/bin/wine64")
            try fileManager.createDirectory(at: wine64.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try Data().write(to: wine64)
            let version = WhiskyWineVersion(
                version: SemanticVersion(1, 0, 0),
                sha256: nil,
                signature: nil
            )
            let versionURL = libraries
                .appending(path: "WhiskyWineVersion")
                .appendingPathExtension("plist")
            try PropertyListEncoder().encode(version).write(to: versionURL)

            let link = root.appending(path: "LinkedLibraries")
            try fileManager.createSymbolicLink(at: link, withDestinationURL: libraries)

            return WhiskyWineInstaller.isRuntimePresent(inLibraryFolder: libraries)
                && !WhiskyWineInstaller.isRuntimePresent(inLibraryFolder: link)
        } catch {
            print("symlink test error: \(error)")
            return false
        }
    }

    static func installVerifierRejectsBadChecksum() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-checksum-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try Data("hello".utf8).write(to: url)
            guard let goodHash = WhiskyWineInstaller.sha256(ofFileAt: url) else { return false }
            var manifest = WhiskyWineVersion(
                version: SemanticVersion(1, 0, 0),
                sha256: goodHash,
                signature: nil
            )
            // Debug builds allow a missing signature; the hash must match.
            try WhiskyWineInstaller.verify(tarball: url, manifest: manifest)

            manifest.sha256 = "0000"
            do {
                try WhiskyWineInstaller.verify(tarball: url, manifest: manifest)
                return false
            } catch {
                return true
            }
        } catch {
            print("checksum test error: \(error)")
            return false
        }
    }

    static func streamedNoNewlineBytes() async -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "head -c 2000000 /dev/zero | tr '\\0' A"]

        guard let stream = try? process.runStream(name: "long-line-test", fileHandle: nil) else {
            return -1
        }

        var total = 0
        for await output in stream {
            if case .message(let message) = output {
                total += message.utf8.count
            }
        }
        return total
    }

    static func bitmapRejectsBadDimensions() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-bitmap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            var data = Data()
            func append<T: FixedWidthInteger>(_ value: T) {
                var value = value.littleEndian
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
            append(UInt32(40))
            append(Int32(100_000))
            append(Int32(-100_000))
            append(UInt16(1))
            append(UInt16(32))
            append(UInt32(0))
            append(UInt32(0))
            append(Int32(0))
            append(Int32(0))
            append(UInt32(0))
            append(UInt32(0))
            try data.write(to: url)

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let header = BitmapInfoHeader(handle: handle, offset: 0)
            return header.renderBitmap(handle: handle, offset: 40) == nil
        } catch {
            print("bitmap test error: \(error)")
            return false
        }
    }

    static func shortcutSizeCap() -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "whisky-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let bottle = Bottle(bottleUrl: root)
            let link = root.appending(path: "huge.lnk")
            try Data(count: 2_000_000).write(to: link)

            let handle = try FileHandle(forReadingFrom: link)
            defer { try? handle.close() }
            return ShellLinkHeader.getProgram(url: link, handle: handle, bottle: bottle) == nil
        } catch {
            print("shortcut test error: \(error)")
            return false
        }
    }
}
