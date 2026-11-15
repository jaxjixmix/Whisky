//
//  Wine+Logging.swift
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

extension Wine {
    public static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.whiskyBundleIdentifier)

    public static func makeFileHandle() throws -> FileHandle {
        let folderPath = Self.logsFolder.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: folderPath) {
            try FileManager.default.createDirectory(
                at: Self.logsFolder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let dateString = Date.now.ISO8601Format()
        // Two runs in the same second used to overwrite each other's log.
        let fileURL = Self.logsFolder
            .appending(path: "\(dateString)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
        return try FileHandle(forWritingTo: fileURL)
    }
}
