#!/usr/bin/env swift
//
//  generate-runtime-manifest.swift
//  Whisky release tools
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

let defaultReleaseBase = "https://github.com/jaxjixmix/Whisky/releases/download"

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    Usage: swift generate-runtime-manifest.swift <Libraries.tar.gz> <version> <ed25519-key> [output.plist]
    The key file is 32 raw bytes or base64 of 32 bytes.
    Set WHISKY_RELEASES_BASE_URL to override the release host.
    """.utf8))
    exit(1)
}

func sha256Hex(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func loadKey(at path: String) -> Data? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    if data.count == 32 { return data }

    guard let text = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          let decoded = Data(base64Encoded: text), decoded.count == 32 else {
        return nil
    }
    return decoded
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else { usage() }

let archive = URL(fileURLWithPath: arguments[1])
let version = arguments[2]
let keyPath = arguments[3]
let outputPath = arguments.count > 4 ? arguments[4] : nil
let releaseBase = ProcessInfo.processInfo
    .environment["WHISKY_RELEASES_BASE_URL"] ?? defaultReleaseBase
let components = version.split(separator: ".").compactMap { Int($0) }
guard components.count == 3 else { usage() }
guard let keyData = loadKey(at: keyPath) else {
    FileHandle.standardError.write(
        Data("Could not read a 32-byte Ed25519 private key.\n".utf8)
    )
    exit(1)
}

do {
    let digest = try sha256Hex(of: archive)
    let downloadURL = "\(releaseBase)/v\(version)/Libraries.tar.gz"
    let payload = "WhiskyWine|\(version)|\(digest)|\(downloadURL)"
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    let signature = try privateKey.signature(for: Data(payload.utf8))
        .base64EncodedString()

    let plist: [String: Any] = [
        "version": [
            "major": components[0],
            "minor": components[1],
            "patch": components[2],
            "preRelease": "",
            "build": ""
        ],
        "sha256": digest,
        "signature": signature
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0
    )

    if let outputPath {
        try data.write(to: URL(fileURLWithPath: outputPath))
    } else {
        FileHandle.standardOutput.write(data)
    }
} catch {
    FileHandle.standardError.write(Data("Failed: \(error)\n".utf8))
    exit(1)
}
