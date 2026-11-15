//
//  SelfTest.swift
//  WhiskyKitSelfTest
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

// swiftlint:disable file_length type_body_length

import Foundation
import SemanticVersion
@testable import WhiskyKit

@main
struct SelfTest {
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

        let lines = await streamedMessages(
            arguments: ["-c", "printf 'one\\ntwo\\npart'; sleep 0.05; printf 'ial\\n'"]
        )
        check(lines == ["one", "two", "partial"], "lines are buffered across reads: \(lines)")

        let eofCount = await messageCountBeforeExit(
            arguments: ["-c", "printf 'done\\n'; sleep 1"],
            waitNanoseconds: 300_000_000
        )
        check(eofCount == 1, "closed pipe stops producing messages: \(eofCount)")

        check(cappedLogStaysBounded(), "log is capped and leaves a truncation marker")

        check(installPreservesRuntimeOnBadArchive(), "a bad runtime archive keeps the installed runtime")
        check(installSwapsInValidRuntime(), "a valid runtime archive replaces the installed runtime")

        check(settingsDecodeCreatesDefaultsForMissingFile(), "missing bottle settings get defaults")
        check(settingsKeepPinsAcrossWineVersionChange(), "a wine-version change keeps name and pins")
        check(settingsQuarantineCorruptFile(), "an unreadable settings file is quarantined")
        check(bottleKeepsPinsForMissingPrograms(), "missing pinned programs are kept")
        check(registryBacksUpCorruptFile(), "a corrupt registry is backed up, not silently dropped")
        check(registryPreservesPathsOnVersionMismatch(), "a registry version change keeps bottle paths")

        check(shellQuotingHandlesMetacharacters(), "shell quoting handles spaces, quotes and substitutions")

        if failures > 0 {
            print("\(failures) self-test(s) failed")
            exit(1)
        }
        print("All WhiskyKit self-tests passed")
    }

    static func streamedMessages(arguments: [String]) async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        guard let stream = try? process.runStream(name: "self-test", fileHandle: nil) else {
            return []
        }

        var messages: [String] = []
        for await output in stream {
            if case .message(let message) = output {
                messages.append(message)
            }
        }
        return messages
    }

    static func shellQuotingHandlesMetacharacters() -> Bool {
        let input = "a b'c$d`e\"f\\g"
        let expected = "'a b'\\''c$d`e\"f\\g'"
        return ShellQuoting.quoted(input) == expected
            && ShellQuoting.quoted("") == "''"
            && ShellQuoting.commandLine(["a", "b c"]) == "'a' 'b c'"
            && ShellQuoting.assignment("KEY", "a b") == "KEY='a b'"
            && ShellQuoting.isValidEnvironmentKey("WINEDEBUG")
            && !ShellQuoting.isValidEnvironmentKey("A-B")
            && !ShellQuoting.isValidEnvironmentKey("1A")
    }

    static func settingsDecodeCreatesDefaultsForMissingFile() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-settings-missing-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            let url = root.appending(path: "Metadata").appendingPathExtension("plist")
            let settings = try BottleSettings.decode(from: url)
            return settings.name == "Bottle" && fileManager.fileExists(atPath: url.path)
        } catch {
            print("settings missing-file test error: \(error)")
            return false
        }
    }

    static func settingsKeepPinsAcrossWineVersionChange() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-settings-version-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appending(path: "Metadata").appendingPathExtension("plist")
            var settings = BottleSettings()
            settings.name = "Keep me"
            settings.wineVersion = SemanticVersion(0, 0, 0)
            settings.pins = [PinnedProgram(name: "Pinned", url: URL(filePath: "/tmp/missing.exe"))]
            try settings.encode(to: url)

            let decoded = try BottleSettings.decode(from: url)
            return decoded.name == "Keep me" && decoded.pins.count == 1
        } catch {
            print("settings version test error: \(error)")
            return false
        }
    }

    static func settingsQuarantineCorruptFile() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-settings-corrupt-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appending(path: "Metadata").appendingPathExtension("plist")
            try Data("not a plist".utf8).write(to: url)

            let decoded = try BottleSettings.decode(from: url)
            let backups = try fileManager.contentsOfDirectory(atPath: root.path)
                .filter { $0.contains(".corrupt-") }
            return decoded.name == "Bottle" && backups.count == 1
        } catch {
            print("settings quarantine test error: \(error)")
            return false
        }
    }

    static func bottleKeepsPinsForMissingPrograms() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-pins-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            var settings = BottleSettings()
            settings.pins = [PinnedProgram(name: "Missing",
                                           url: root.appending(path: "drive_c/missing.exe"))]
            try settings.encode(to: root.appending(path: "Metadata").appendingPathExtension("plist"))

            let bottle = Bottle(bottleUrl: root)
            return bottle.settings.pins.count == 1
        } catch {
            print("pin retention test error: \(error)")
            return false
        }
    }

    static func registryBacksUpCorruptFile() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-registry-corrupt-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appending(path: "BottleVM").appendingPathExtension("plist")
            try Data("not a plist".utf8).write(to: file)

            let data = BottleData(entriesFile: file)
            let backups = try fileManager.contentsOfDirectory(atPath: root.path)
                .filter { $0.contains(".corrupt-") }
            let reloaded = BottleData(entriesFile: file)
            return data.paths.isEmpty && backups.count == 1 && reloaded.paths.isEmpty
        } catch {
            print("registry corrupt test error: \(error)")
            return false
        }
    }

    static func registryPreservesPathsOnVersionMismatch() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-registry-version-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appending(path: "BottleVM").appendingPathExtension("plist")
            let bottleURL = URL(filePath: "/tmp/whisky-bottle")

            var data = BottleData(entriesFile: file)
            data.paths = [bottleURL]

            var plist = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: file), options: [], format: nil
            ) as? [String: Any]
            plist?["fileVersion"] = ["major": 0, "minor": 9, "patch": 0, "preRelease": "", "build": ""]
            let oldData = try PropertyListSerialization.data(
                fromPropertyList: plist as Any, format: .xml, options: 0
            )
            try oldData.write(to: file)

            let reloaded = BottleData(entriesFile: file)
            return reloaded.paths == [bottleURL]
        } catch {
            print("registry version test error: \(error)")
            return false
        }
    }

    static func installPreservesRuntimeOnBadArchive() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-install-bad-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            let destination = root.appending(path: "Support")
            let live = destination.appending(path: "Libraries")
            let wine64 = live.appending(path: "Wine/bin/wine64")
            try fileManager.createDirectory(at: wine64.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try Data("old".utf8).write(to: wine64)
            try writeVersion(at: live)

            let badArchive = root.appending(path: "bad.tar.gz")
            try Data("not a tar".utf8).write(to: badArchive)

            do {
                try WhiskyWineInstaller.install(tarball: badArchive, into: destination)
                return false
            } catch {
                let contents = try String(contentsOf: wine64, encoding: .utf8)
                return contents == "old"
            }
        } catch {
            print("install failure test error: \(error)")
            return false
        }
    }

    static func installSwapsInValidRuntime() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(path: "whisky-install-good-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }

        do {
            let destination = root.appending(path: "Support")
            let live = destination.appending(path: "Libraries")
            let liveWine64 = live.appending(path: "Wine/bin/wine64")
            try fileManager.createDirectory(at: liveWine64.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try Data("old".utf8).write(to: liveWine64)
            try writeVersion(at: live)

            let stage = root.appending(path: "stage")
            let stagedLibraries = stage.appending(path: "Libraries")
            let stagedWine64 = stagedLibraries.appending(path: "Wine/bin/wine64")
            try fileManager.createDirectory(at: stagedWine64.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try Data("new".utf8).write(to: stagedWine64)
            try writeVersion(at: stagedLibraries)

            let archive = root.appending(path: "Libraries.tar.gz")
            guard makeTar(folder: stage, archive: archive) else { return false }

            try WhiskyWineInstaller.install(tarball: archive, into: destination)
            let contents = try String(contentsOf: liveWine64, encoding: .utf8)
            return contents == "new" && !fileManager.fileExists(atPath: archive.path)
        } catch {
            print("install success test error: \(error)")
            return false
        }
    }

    static func writeVersion(at libraries: URL) throws {
        try FileManager.default.createDirectory(at: libraries, withIntermediateDirectories: true)
        let url = libraries.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        let data = try PropertyListEncoder().encode(WhiskyWineVersion())
        try data.write(to: url)
    }

    static func makeTar(folder: URL, archive: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-C", folder.path(percentEncoded: false), "-zcf",
                             archive.path(percentEncoded: false), "."]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("tar error: \(error)")
            return false
        }
    }

    static func cappedLogStaysBounded() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-log-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try Data().write(to: url)
            let handle = try FileHandle(forWritingTo: url)
            let line = String(repeating: "a", count: 100_000) + "\n"
            let writes = Int(FileHandle.maxLogSize / 100_000) + 2
            for _ in 0..<writes {
                handle.write(line: line)
            }
            try handle.close()

            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let contents = try String(contentsOf: url, encoding: .utf8)
            return size <= Int(FileHandle.maxLogSize) + line.utf8.count
                && contents.contains("log truncated")
                && contents.hasSuffix(line)
        } catch {
            print("log cap test error: \(error)")
            return false
        }
    }

    static func messageCountBeforeExit(arguments: [String], waitNanoseconds: UInt64) async -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        guard let stream = try? process.runStream(name: "self-test-eof", fileHandle: nil) else {
            return -1
        }

        let counter = Task { () -> Int in
            var count = 0
            for await output in stream {
                if case .message = output {
                    count += 1
                }
            }
            return count
        }
        try? await Task.sleep(nanoseconds: waitNanoseconds)
        counter.cancel()
        process.terminate()
        return await counter.value
    }
}
