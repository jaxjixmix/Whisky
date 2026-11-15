//
//  EditMenuToggle.swift
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

import SwiftUI
import WhiskyKit

struct EditMenuToggle: View {
    @ObservedObject var bottle: Bottle
    @State private var enabled: Bool = true
    @State private var loadingState: LoadingState = .loading

    var body: some View {
        SettingItemView(title: "config.editMenu", loadingState: loadingState) {
            Toggle("config.editMenu", isOn: $enabled)
                .onChange(of: enabled, { _, newValue in
                    Task(priority: .userInitiated) {
                        loadingState = .modifying
                        do {
                            try await Wine.changeEditMenu(bottle: bottle, enabled: newValue)
                            loadingState = .success
                        } catch {
                            print("Failed to change edit menu")
                            loadingState = .failed
                        }
                    }
                })
        }
        .onAppear {
            Task(priority: .userInitiated) {
                do {
                    enabled = try await Wine.isEditMenuEnabled(bottle: bottle)
                    loadingState = .success
                } catch {
                    print(error)
                    loadingState = .failed
                }
            }
        }
    }
}
