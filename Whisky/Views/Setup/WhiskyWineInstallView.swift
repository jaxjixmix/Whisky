//
//  WhiskyWineInstallView.swift
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

struct WhiskyWineInstallView: View {
    @State var installing: Bool = true
    @State private var installError: String?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.install")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.install.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if installing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 80)
                } else if let installError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.yellow)
                        Text(installError)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Button("button.retry") {
                            startInstall()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            startInstall()
        }
    }

    private func startInstall() {
        installing = true
        installError = nil

        let tarball = tarLocation
        Task.detached {
            let result: Result<Void, Error>
            do {
                try WhiskyWineInstaller.install(from: tarball)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                installing = false
                switch result {
                case .success:
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        proceed()
                    }
                case .failure(let error):
                    installError = (error as? LocalizedError)?.errorDescription
                        ?? String(describing: error)
                }
            }
        }
    }

    @MainActor
    func proceed() {
        showSetup = false
    }
}
