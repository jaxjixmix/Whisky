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
    case checksumMismatch
    case invalidSignature
    case missingIntegrityMetadata
    case manifestUnavailable

    public var errorDescription: String? {
        switch self {
        case .tarballMissing:
            return "The downloaded runtime archive is missing."
        case .invalidArchive:
            return "The downloaded archive does not contain a usable Wine runtime."
        case .checksumMismatch:
            return "The downloaded runtime does not match its checksum."
        case .invalidSignature:
            return "The runtime manifest signature is invalid."
        case .missingIntegrityMetadata:
            return "The runtime manifest is not signed; refusing to install it."
        case .manifestUnavailable:
            return "Could not fetch the signed runtime manifest."
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

    public static let downloadURLString = "https://data.getwhisky.app/Wine/Libraries.tar.gz"
    public static let versionPlistURLString = "https://data.getwhisky.app/Wine/WhiskyWineVersion.plist"
    static let maxManifestBytes = 1_048_576

    public static var downloadURL: URL? {
        URL(string: downloadURLString)
    }

    public static func isWhiskyWineInstalled() -> Bool {
        return isRuntimePresent(inLibraryFolder: libraryFolder)
    }

    /// Whether `folder` contains both the version record and the `wine64`
    /// binary. A half-extracted runtime must not count as installed.
    static func isRuntimePresent(inLibraryFolder folder: URL) -> Bool {
        guard isRegularDirectory(folder) else { return false }

        let versionPlist = folder
            .appending(path: "WhiskyWineVersion")
            .appendingPathExtension("plist")
        guard isRegularFile(versionPlist), whiskyWineInfo(at: versionPlist) != nil else {
            return false
        }

        let wine64 = folder
            .appending(path: "Wine")
            .appending(path: "bin")
            .appending(path: "wine64")
        return isRegularFile(wine64)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func isRegularDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    /// Fetch the manifest, verify the archive, then install it. Release builds
    /// require a signed manifest; debug builds warn and continue.
    public static func install(from tarball: URL) async throws {
        guard let manifest = await fetchRemoteVersion() else {
            #if DEBUG
            Logger.wineKit.warning("Runtime manifest unavailable; installing without integrity metadata")
            try install(tarball: tarball, into: applicationFolder)
            return
            #else
            throw WhiskyWineInstallError.manifestUnavailable
            #endif
        }

        try verify(tarball: tarball, manifest: manifest)
        try install(tarball: tarball, into: applicationFolder)
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
        guard let localVersion = whiskyWineVersion(),
              let remote = await fetchRemoteVersion() else {
            return (false, SemanticVersion(0, 0, 0))
        }

        #if !DEBUG
        // Do not offer an update the installer would refuse.
        guard remote.sha256 != nil, remote.signature != nil else {
            Logger.wineKit.warning("Ignoring an unsigned WhiskyWine manifest in a release build")
            return (false, SemanticVersion(0, 0, 0))
        }
        #endif

        guard localVersion < remote.version else {
            return (false, SemanticVersion(0, 0, 0))
        }
        return (true, remote.version)
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
            let path = versionPlist.path(percentEncoded: false)
            let message = "Failed to read WhiskyWine version at \(path): \(error)"
            Logger.wineKit.error("\(message, privacy: .public)")
            return nil
        }
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
    var sha256: String?
    var signature: String?

    /// Canonical payload the release pipeline signs.
    var signingPayload: String {
        "WhiskyWine|\(version)|\(sha256 ?? "")|\(WhiskyWineInstaller.downloadURLString)"
    }
}
