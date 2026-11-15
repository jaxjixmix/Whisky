//
//  ShellQuoting.swift
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

/// Single-quote shell words so paths and user-editable settings cannot be
/// interpreted as shell syntax.
public enum ShellQuoting {
    /// Quote one word for a POSIX shell. Single quotes are escaped with
    /// `'\''`, which every POSIX shell understands.
    public static func quoted(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Quote each word and join them with spaces.
    public static func commandLine(_ words: [String]) -> String {
        words.map(quoted).joined(separator: " ")
    }

    /// Build a `NAME=value` assignment with a single-quoted value.
    public static func assignment(_ name: String, _ value: String) -> String {
        "\(name)=\(quoted(value))"
    }

    /// Environment keys are passed straight to the shell; only accept the
    /// portable identifier form.
    public static func isValidEnvironmentKey(_ key: String) -> Bool {
        guard let first = key.first, first.isASCII,
              first.isLetter || first == "_" else { return false }
        return key.dropFirst().allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }
}
