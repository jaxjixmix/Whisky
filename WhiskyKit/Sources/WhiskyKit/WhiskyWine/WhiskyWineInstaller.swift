//
//  WhiskyWineInstaller.swift
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

public enum WhiskyWineInstallError: LocalizedError {
    case tarballMissing
    case invalidArchive

    public var errorDescription: String? {
        switch self {
        case .tarballMissing:
            return "The downloaded runtime archive is missing."
        case .invalidArchive:
            return "The downloaded archive does not contain a usable Wine runtime."
        }
    }
}

public class WhiskyWineInstaller {
    /// The Whisky application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    public static func isWhiskyWineInstalled() -> Bool {
        return isRuntimePresent(inLibraryFolder: libraryFolder)
    }

    /// Whether `folder` contains both the version record and the `wine64`
    /// binary. A half-extracted runtime must not count as installed.
    static func isRuntimePresent(inLibraryFolder folder: URL) -> Bool {
        let versionPlist = folder
            .appending(path: "WhiskyWineVersion")
            .appendingPathExtension("plist")
        guard whiskyWineInfo(at: versionPlist) != nil else { return false }

        let wine64 = folder
            .appending(path: "Wine")
            .appending(path: "bin")
            .appending(path: "wine64")
        return FileManager.default.fileExists(atPath: wine64.path(percentEncoded: false))
    }

    /// Extract into a staging directory, validate it, then swap it in. A bad
    /// archive leaves the installed runtime untouched (upstream #1275/#1278).
    public static func install(from: URL) throws {
        try install(tarball: from, into: applicationFolder)
    }

    static func install(tarball: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: tarball.path(percentEncoded: false)) else {
            throw WhiskyWineInstallError.tarballMissing
        }

        let staging = fileManager.temporaryDirectory
            .appending(path: "whisky-runtime-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        try Tar.untar(tarBall: tarball, toURL: staging)

        // The published archive contains Libraries/ at its root.
        let stagedLibraries = staging.appending(path: "Libraries")
        guard isRuntimePresent(inLibraryFolder: stagedLibraries) else {
            throw WhiskyWineInstallError.invalidArchive
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let liveLibraries = destination.appending(path: "Libraries")
        let backup = destination.appending(path: "Libraries.backup-\(UUID().uuidString)")

        if fileManager.fileExists(atPath: liveLibraries.path(percentEncoded: false)) {
            try fileManager.moveItem(at: liveLibraries, to: backup)
        }

        do {
            try fileManager.moveItem(at: stagedLibraries, to: liveLibraries)
            try? fileManager.removeItem(at: backup)
        } catch {
            try? fileManager.removeItem(at: liveLibraries)
            if fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
                try? fileManager.moveItem(at: backup, to: liveLibraries)
            }
            throw error
        }

        try? fileManager.removeItem(at: tarball)
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall WhiskyWine: \(error)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let versionPlistURL = "https://data.getwhisky.app/Wine/WhiskyWineVersion.plist"
        let localVersion = whiskyWineVersion()

        var remoteVersion: SemanticVersion?

        if let remoteUrl = URL(string: versionPlistURL) {
            remoteVersion = await withCheckedContinuation { continuation in
                URLSession(configuration: .ephemeral).dataTask(with: URLRequest(url: remoteUrl)) { data, _, error in
                    do {
                        if error == nil, let data = data {
                            let decoder = PropertyListDecoder()
                            let remoteInfo = try decoder.decode(WhiskyWineVersion.self, from: data)
                            let remoteVersion = remoteInfo.version

                            continuation.resume(returning: remoteVersion)
                            return
                        }
                        if let error = error {
                            print(error)
                        }
                    } catch {
                        print(error)
                    }

                    continuation.resume(returning: nil)
                }.resume()
            }
        }

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        let versionPlist = libraryFolder
            .appending(path: "WhiskyWineVersion")
            .appendingPathExtension("plist")
        return whiskyWineInfo(at: versionPlist)?.version
    }

    private static func whiskyWineInfo(at versionPlist: URL) -> WhiskyWineVersion? {
        guard FileManager.default.fileExists(atPath: versionPlist.path(percentEncoded: false)) else {
            return nil
        }
        do {
            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WhiskyWineVersion.self, from: data)
            return info
        } catch {
            Logger.wineKit.error(
                "Failed to read WhiskyWine version at \(versionPlist.path(percentEncoded: false), privacy: .public): \(error, privacy: .public)"
            )
            return nil
        }
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
