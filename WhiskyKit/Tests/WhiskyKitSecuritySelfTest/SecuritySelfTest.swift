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
}
