//
//  Wine+ProcessControl.swift
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
import os.log

extension Wine {
    /// Run `wineserver -k` and wait for it, so quitting the app cannot return
    /// before the bottle's processes have been asked to close.
    ///
    /// - Returns: `true` when `wineserver` exited successfully within `timeout`.
    @discardableResult
    public static func killBottleAndWait(bottle: Bottle, timeout: TimeInterval = 5) -> Bool {
        let process = Process()
        process.executableURL = wineserverBinary
        process.arguments = ["-k"]
        process.currentDirectoryURL = wineserverBinary.deletingLastPathComponent()
        process.environment = constructWineServerEnvironment(for: bottle)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Logger.wineKit.error(
                "Failed to start wineserver for '\(bottle.settings.name, privacy: .public)': \(error, privacy: .public)"
            )
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            Logger.wineKit.warning(
                "wineserver -k timed out for '\(bottle.settings.name, privacy: .public)'"
            )
            process.terminate()
            process.waitUntilExit()
            return false
        }
        return process.terminationStatus == 0
    }
}
