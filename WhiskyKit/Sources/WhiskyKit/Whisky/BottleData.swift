//
//  BottleData.swift
//  WhiskyKit
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

import Foundation
import SemanticVersion
import os.log

public struct BottleData: Codable {
    public static let containerDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library")
        .appending(path: "Containers")
        .appending(path: Bundle.whiskyBundleIdentifier)

    public static let bottleEntriesDir = containerDir
        .appending(path: "BottleVM")
        .appendingPathExtension("plist")

    public static let defaultBottleDir = containerDir
        .appending(path: "Bottles")

    static let currentVersion = SemanticVersion(1, 0, 0)

    private enum CodingKeys: String, CodingKey {
        case fileVersion
        case paths
    }

    private var fileVersion: SemanticVersion
    /// The registry file this value was loaded from. Excluded from Codable so the
    /// on-disk format stays `{ fileVersion, paths }`.
    private var entriesFile: URL = Self.bottleEntriesDir
    public var paths: [URL] = [] {
        didSet {
            encode()
        }
    }

    public init() {
        self.init(entriesFile: Self.bottleEntriesDir)
    }

    init(entriesFile: URL) {
        self.entriesFile = entriesFile
        fileVersion = Self.currentVersion

        if !decode() {
            encode()
        }
    }

    public mutating func loadBottles() -> [Bottle] {
        var bottles: [Bottle] = []

        for path in paths {
            let bottleMetadata = path
                .appending(path: "Metadata")
                .appendingPathExtension("plist")
                .path(percentEncoded: false)

            if FileManager.default.fileExists(atPath: bottleMetadata) {
                bottles.append(Bottle(bottleUrl: path, isAvailable: true))
            } else {
                bottles.append(Bottle(bottleUrl: path))
            }
        }

        return bottles
    }

    @discardableResult
    private mutating func decode() -> Bool {
        let registryPath = entriesFile.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: registryPath) else {
            // First run: `init` writes an empty registry.
            return false
        }

        guard let data = try? Data(contentsOf: entriesFile) else {
            // The file exists but cannot be read. Rewriting it here would
            // destroy a registry we could not understand.
            Logger.wineKit.error(
                "Failed to read bottle registry at \(registryPath, privacy: .public); leaving it untouched"
            )
            return true
        }

        do {
            let decoded = try PropertyListDecoder().decode(BottleData.self, from: data)
            let fileURL = entriesFile
            self = decoded
            self.entriesFile = fileURL

            let loadedVersion = fileVersion
            if loadedVersion != Self.currentVersion {
                let versionMessage = "Bottle registry version \(loadedVersion); "
                    + "rewriting as \(Self.currentVersion)"
                Logger.wineKit.warning("\(versionMessage, privacy: .public)")
                // Keep the registered paths and let `init` re-encode the
                // current format instead of discarding the list.
                fileVersion = Self.currentVersion
                return false
            }
            return true
        } catch {
            let backup = Self.backUpCorruptRegistry(at: entriesFile)
            let backupPath = backup?.path(percentEncoded: false) ?? "(failed)"
            let decodeMessage = "Failed to decode bottle registry: \(error); "
                + "backed up to \(backupPath)"
            Logger.wineKit.error("\(decodeMessage, privacy: .public)")
            return false
        }
    }

    @discardableResult
    private func encode() -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            try FileManager.default.createDirectory(
                at: entriesFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(self)
            try data.write(to: entriesFile)
            return true
        } catch {
            let registryPath = entriesFile.path(percentEncoded: false)
            let writeMessage = "Failed to write bottle registry at \(registryPath): \(error)"
            Logger.wineKit.error("\(writeMessage, privacy: .public)")
            return false
        }
    }

    /// Move an unreadable registry aside before a fresh one is written.
    private static func backUpCorruptRegistry(at file: URL) -> URL? {
        let name = file.deletingPathExtension().lastPathComponent
        let stamp = Int(Date.now.timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(8)
        let backup = file.deletingLastPathComponent()
            .appending(path: "\(name).corrupt-\(stamp)-\(suffix)")
            .appendingPathExtension("plist")
        do {
            try FileManager.default.moveItem(at: file, to: backup)
            return backup
        } catch {
            Logger.wineKit.error(
                "Failed to back up corrupt bottle registry: \(error, privacy: .public)"
            )
            return nil
        }
    }
}
