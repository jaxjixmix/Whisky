//
//  BottleVM.swift
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
import SemanticVersion
import WhiskyKit
import os.log

// swiftlint:disable:next todo
// TODO: Don't use unchecked!
final class BottleVM: ObservableObject, @unchecked Sendable {
    @MainActor static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []
    /// Set when a bottle was created but its Wine prefix could not be prepared.
    /// The bottle stays registered so the user can retry or remove it.
    @Published var creationError: String?

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        Task.detached {
            var bottle: Bottle?
            do {
                try FileManager.default.createDirectory(atPath: newBottleDir.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let newBottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottle = newBottle

                // Register and save before Wine runs. A Wine failure must not
                // leave a bottle directory that no later launch knows about.
                await MainActor.run {
                    newBottle.settings.name = bottleName
                    newBottle.settings.windowsVersion = winVersion
                    if !self.bottlesList.paths.contains(newBottleDir) {
                        self.bottlesList.paths.append(newBottleDir)
                    }
                    self.bottles.append(newBottle)
                    self.creationError = nil
                }

                try await Wine.changeWinVersion(bottle: newBottle, win: winVersion)
                let wineVer = try await Wine.wineVersion()

                await MainActor.run {
                    newBottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)
                    newBottle.inFlight = false
                    newBottle.isAvailable = true
                    self.loadBottles()
                }
            } catch {
                Logger.wineKit.error("Failed to create bottle: \(error, privacy: .public)")
                if let bottle {
                    // Keep the bottle visible and usable: the directory and
                    // metadata exist, and Wine may succeed on a retry.
                    await MainActor.run {
                        bottle.inFlight = false
                        bottle.isAvailable = true
                        self.loadBottles()
                        self.creationError = error.localizedDescription
                    }
                } else {
                    await MainActor.run {
                        self.creationError = error.localizedDescription
                    }
                }
            }
        }
        return newBottleDir
    }
}
