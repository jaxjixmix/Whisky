//
//  Bottle+Extensions.swift
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

/// Helper, crash-reporter and redistributable executables that should not
/// appear in the user's program list (upstream #1215 and launcher noise).
private let noiseExecutables: Set<String> = [
    "steamerrorreporter.exe",
    "steamerrorreporter64.exe",
    "steamservice.exe",
    "steamwebhelper.exe",
    "steam_monitor.exe",
    "steamsysinfo.exe",
    "steamxboxutil.exe",
    "crashreporter.exe",
    "crashhandler.exe",
    "crashpad_handler.exe",
    "gameoverlayui.exe",
    "gameoverlayui64.exe",
    "fossilize-replay.exe",
    "fossilize-replay64.exe",
    "gldriverquery.exe",
    "gldriverquery64.exe",
    "hardwareupdater.exe",
    "secure_desktop_capture.exe",
    "writeminidump.exe",
    "vc_redist.x86.exe",
    "vc_redist.x64.exe",
    "vcredist_x86.exe",
    "vcredist_x64.exe",
    "ueprereqsetup_x86.exe",
    "ueprereqsetup_x64.exe",
    "crossover html engine.exe"
]

extension Bottle {
    func openCDrive() {
        NSWorkspace.shared.open(url.appending(path: "drive_c"))
    }

    func openTerminal() {
        let whiskyCmdURL = Bundle.main.url(forResource: "WhiskyCmd", withExtension: nil)
        if let whiskyCmdURL = whiskyCmdURL {
            let whiskyCmd = whiskyCmdURL.path(percentEncoded: false)
            let cmd = "eval \"$(\(ShellQuoting.quoted(whiskyCmd)) shellenv \(ShellQuoting.quoted(settings.name)))\""

            let script = """
            tell application "Terminal"
            activate
            do script "\(cmd.appleScriptQuoted)"
            end tell
            """

            Task.detached(priority: .userInitiated) {
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else { return }
                appleScript.executeAndReturnError(&error)

                if let error = error {
                    Logger.wineKit.error("Failed to run terminal script \(error)")
                    guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                    await self.showRunError(message: String(describing: description))
                }
            }
        }
    }

    @discardableResult
    func getStartMenuPrograms() -> [Program] {
        var startMenuPrograms: [Program] = []
        let alreadyImported = Set(settings.importedShortcuts)
        var newlyImported: [URL] = []

        for link in startMenuLinkURLs() where !alreadyImported.contains(link) {
            do {
                if let program = ShellLinkHeader.getProgram(url: link,
                                                            handle: try FileHandle(forReadingFrom: link),
                                                            bottle: self) {
                    if !startMenuPrograms.contains(where: { $0.url == program.url }) {
                        startMenuPrograms.append(program)
                    }
                    // Keep the .lnk: it belongs to the bottle, and importing
                    // it again after an unpin would silently re-pin it.
                    newlyImported.append(link)
                }
            } catch {
                print(error)
            }
        }

        if !newlyImported.isEmpty {
            settings.importedShortcuts.append(contentsOf: newlyImported)
        }

        return startMenuPrograms
    }

    /// Both Start Menu trees, sorted by shortcut name.
    private func startMenuLinkURLs() -> [URL] {
        let menus = [
            url.appending(path: "drive_c/ProgramData/Microsoft/Windows/Start Menu"),
            url.appending(path: "drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu")
        ]
        var linkURLs: [URL] = []

        for menu in menus {
            let enumerator = FileManager.default.enumerator(
                at: menu, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            )
            while let item = enumerator?.nextObject() as? URL {
                if item.pathExtension == "lnk" {
                    linkURLs.append(item)
                }
            }
        }

        return linkURLs.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    }

    @MainActor
    func updateInstalledPrograms() async {
        let driveC = url.appending(path: "drive_c")
        let blocklist = settings.blocklist
        let pins = settings.pins
        let bottle = self

        let programs = await Task.detached(priority: .userInitiated) {
            Self.scanInstalledPrograms(driveC: driveC, blocklist: blocklist, pins: pins, bottle: bottle)
        }.value

        self.programs = programs
    }

    /// Filesystem walk and PE/settings parsing; safe to run off the main actor.
    private static func scanInstalledPrograms(
        driveC: URL,
        blocklist: [URL],
        pins: [PinnedProgram],
        bottle: Bottle
    ) -> [Program] {
        var programs: [Program] = []
        var foundURLs: Set<URL> = []

        for folderName in ["Program Files", "Program Files (x86)"] {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath && url.pathExtension == "exe" else { continue }
                guard !noiseExecutables.contains(url.lastPathComponent.lowercased()) else { continue }
                guard !blocklist.contains(url) else { continue }
                foundURLs.insert(url)
                programs.append(Program(url: url, bottle: bottle,
                                        pinned: pins.contains(where: { $0.url == url })))
            }
        }

        // Add missing programs from pins.
        for pin in pins {
            guard let url = pin.url, !foundURLs.contains(url) else { continue }
            programs.append(Program(url: url, bottle: bottle, pinned: true))
        }

        return programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    @MainActor
    func move(destination: URL) {
        let oldBottleURL = url
        let movedBottle = BottleVM.shared.bottles.first(where: { $0.url == oldBottleURL })
        let originalPins = movedBottle?.settings.pins
        let originalBlocklist = movedBottle?.settings.blocklist
        let originalShortcuts = movedBottle?.settings.importedShortcuts

        do {
            if let bottle = movedBottle {
                bottle.inFlight = true
                rewriteMovedPaths(in: bottle, from: oldBottleURL, to: destination)
            }
            try FileManager.default.moveItem(at: oldBottleURL, to: destination)
            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: oldBottleURL) {
                BottleVM.shared.bottlesList.paths[path] = destination
            }
            BottleVM.shared.loadBottles()
        } catch {
            // The directory did not move: put the rewritten paths back so the
            // bottle's settings still point inside the old location.
            if let bottle = movedBottle {
                if let originalPins {
                    bottle.settings.pins = originalPins
                }
                if let originalBlocklist {
                    bottle.settings.blocklist = originalBlocklist
                }
                if let originalShortcuts {
                    bottle.settings.importedShortcuts = originalShortcuts
                }
            }
            print("Failed to move bottle: \(error)")
        }
    }

    /// Rewrite settings that store absolute paths after the directory move.
    private func rewriteMovedPaths(in bottle: Bottle, from oldURL: URL, to destination: URL) {
        for index in 0..<bottle.settings.pins.count {
            let pin = bottle.settings.pins[index]
            if let pinURL = pin.url {
                bottle.settings.pins[index].url = pinURL.updateParentBottle(old: oldURL,
                                                                            new: destination)
            }
        }

        for index in 0..<bottle.settings.blocklist.count {
            bottle.settings.blocklist[index] = bottle.settings.blocklist[index]
                .updateParentBottle(old: oldURL, new: destination)
        }

        for index in 0..<bottle.settings.importedShortcuts.count {
            bottle.settings.importedShortcuts[index] = bottle.settings.importedShortcuts[index]
                .updateParentBottle(old: oldURL, new: destination)
        }
    }

    func exportAsArchive(destination: URL) {
        do {
            try Tar.tar(folder: url, toURL: destination)
        } catch {
            print("Failed to export bottle")
        }
    }

    @MainActor
    func remove(delete: Bool) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
            }

            if delete {
                try FileManager.default.removeItem(at: url)
            }

            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths.remove(at: path)
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to remove bottle")
        }
    }

    @MainActor
    func rename(newName: String) {
        settings.name = newName
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
