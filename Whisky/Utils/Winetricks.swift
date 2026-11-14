//
//  Winetricks.swift
//  Whisky
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
import AppKit
import WhiskyKit
import os.log

enum WinetricksCategories: String {
    case apps
    case benchmarks
    case dlls
    case fonts
    case games
    case settings
}

struct WinetricksVerb: Identifiable {
    var id = UUID()

    var name: String
    var description: String
}

struct WinetricksCategory {
    var category: WinetricksCategories
    var verbs: [WinetricksVerb]
}

class Winetricks {
    static let winetricksURL: URL = WhiskyWineInstaller.libraryFolder
        .appending(path: "winetricks")

    @MainActor
    static func runCommand(command: String, bottle: Bottle) async {
        guard let resourcesURL = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent() else {
            Logger.wineKit.error("Winetricks resources (cabextract) are missing")
            return
        }

        let scriptURL: URL
        do {
            scriptURL = try makeScript(command: command, bottle: bottle, resourcesURL: resourcesURL)
        } catch {
            Logger.wineKit.error("Failed to write winetricks script: \(error)")
            showError(command: command, description: error.localizedDescription)
            return
        }

        // A temp script avoids passing shell syntax through the user's login
        // shell (fish/xonsh/nushell), which does not accept `VAR=... cmd`.
        let shellCommand = "bash \(ShellQuoting.quoted(scriptURL.path(percentEncoded: false)))"
        let script = """
        tell application "Terminal"
            activate
            do script "\(shellCommand.appleScriptQuoted)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                Logger.wineKit.error("AppleScript error: \(error)")
                if let description = error["NSAppleScriptErrorMessage"] as? String {
                    showError(command: command, description: description)
                }
            }
        }
    }

    private static func makeScript(command: String, bottle: Bottle, resourcesURL: URL) throws -> URL {
        let pathPrefix = "\(WhiskyWineInstaller.binFolder.path(percentEncoded: false)):"
            + "\(resourcesURL.path(percentEncoded: false))"
        let body = """
        #!/bin/bash
        trap 'rm -f -- "$0"' EXIT
        export PATH=\(ShellQuoting.quoted(pathPrefix)):"$PATH"
        export WINE=wine64
        export \(ShellQuoting.assignment("WINEPREFIX", bottle.url.path(percentEncoded: false)))
        \(ShellQuoting.commandLine([winetricksURL.path(percentEncoded: false), command]))
        """

        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-winetricks-\(UUID().uuidString).sh")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    @MainActor
    private static func showError(command: String, description: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
            + " \(command): "
            + description
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }

    static func parseVerbs() async -> [WinetricksCategory] {
        // Grab the verbs file
        let verbsURL = WhiskyWineInstaller.libraryFolder.appending(path: "verbs.txt")
        let verbs: String
        do {
            // `verbs.txt` is a local file, not a network resource.
            verbs = try String(contentsOf: verbsURL, encoding: .utf8)
        } catch {
            Logger.wineKit.error("Failed to read winetricks verbs: \(error)")
            return []
        }

        // Read the file line by line
        let lines = verbs.components(separatedBy: "\n")
        var categories: [WinetricksCategory] = []
        var currentCategory: WinetricksCategory?

        for line in lines {
            // Categories are label as "===== <name> ====="
            if line.starts(with: "=====") {
                // If we have a current category, add it to the list
                if let currentCategory = currentCategory {
                    categories.append(currentCategory)
                }

                // Create a new category
                // Capitalize the first letter of the category name
                let categoryName = line.replacingOccurrences(of: "=====", with: "").trimmingCharacters(in: .whitespaces)
                if let cateogry = WinetricksCategories(rawValue: categoryName) {
                    currentCategory = WinetricksCategory(category: cateogry,
                                                         verbs: [])
                } else {
                    currentCategory = nil
                }
            } else {
                guard currentCategory != nil else {
                    continue
                }

                // If we have a current category, add the verb to it
                // Verbs eg. "3m_library               3M Cloud Library (3M Company, 2015) [downloadable]"
                let verbName = line.components(separatedBy: " ")[0]
                let verbDescription = line.replacingOccurrences(of: "\(verbName) ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentCategory?.verbs.append(WinetricksVerb(name: verbName, description: verbDescription))
            }
        }

        // Add the last category
        if let currentCategory = currentCategory {
            categories.append(currentCategory)
        }

        return categories
    }
}
