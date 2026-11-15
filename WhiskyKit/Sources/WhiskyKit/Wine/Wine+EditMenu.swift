//
//  Wine+EditMenu.swift
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
    /// Whether Wine's mac-driver Edit menu (Cmd-A/C/V mapped to Windows
    /// select-all/copy/paste) is enabled. Wine enables it when the empty
    /// `EditMenu` value is absent.
    public static func isEditMenuEnabled(bottle: Bottle) async throws -> Bool {
        let output = try await runWine(
            ["reg", "query", RegistryKey.macDriver.rawValue, "-v", "EditMenu"],
            bottle: bottle
        )
        let hasEmptyEditMenu = output
            .split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("EditMenu") }
        return !hasEmptyEditMenu
    }

    public static func changeEditMenu(bottle: Bottle, enabled: Bool) async throws {
        if enabled {
            // Wine's default is enabled; remove the suppressing empty value.
            try await runWine(
                ["reg", "delete", RegistryKey.macDriver.rawValue, "-v", "EditMenu", "-f"],
                bottle: bottle
            )
        } else {
            try await addRegistryKey(
                bottle: bottle, key: RegistryKey.macDriver.rawValue,
                name: "EditMenu", data: "", type: .string
            )
        }
    }
}
