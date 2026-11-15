//
//  FileHandleLogCapTests.swift
//  WhiskyKitTests
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

import XCTest
@testable import WhiskyKit

final class FileHandleLogCapTests: XCTestCase {
    /// Wine logs must stay bounded even under error spam (upstream #1261, #1115)
    func testLogRestartsAtCap() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-log-cap-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)

        let handle = try FileHandle(forWritingTo: url)
        let line = String(repeating: "a", count: 100_000) + "\n"
        for _ in 0...(FileHandle.maxLogSize / 100_000 + 1) {
            handle.write(line: line)
        }
        try handle.close()

        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertLessThanOrEqual(try XCTUnwrap(size), Int(FileHandle.maxLogSize) + line.utf8.count)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("log truncated"), "cap should leave a truncation marker")
        XCTAssertTrue(contents.hasSuffix(line), "writes must continue after the cap")
    }
}
