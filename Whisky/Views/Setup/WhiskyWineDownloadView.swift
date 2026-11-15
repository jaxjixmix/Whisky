//
//  WhiskyWineDownloadView.swift
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

struct WhiskyWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var downloadError: String?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // A stalled connection used to hang the setup screen forever.
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration)
    }()

    private var isIndeterminate: Bool {
        totalBytes <= 0
    }

    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.download")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.download.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()

                if let downloadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.yellow)
                        Text(downloadError)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Button("button.retry") {
                            startDownload()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack {
                        if isIndeterminate {
                            ProgressView()
                        } else {
                            ProgressView(value: fractionProgress, total: 1)
                        }
                        HStack {
                            HStack {
                                Text(progressText)
                                    + Text(" ")
                                    + (shouldShowEstimate()
                                       ? Text(etaText)
                                       : Text(String()))
                                Spacer()
                            }
                            .font(.subheadline)
                            .monospacedDigit()
                        }
                    }
                    .padding(.horizontal)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            startDownload()
        }
        .onDisappear {
            downloadTask?.cancel()
            observation?.invalidate()
            observation = nil
        }
    }

    private var progressText: String {
        if isIndeterminate {
            return String(format: String(localized: "setup.whiskywine.progress.unknown"),
                          formatBytes(bytes: completedBytes))
        }
        return String(format: String(localized: "setup.whiskywine.progress"),
                      formatBytes(bytes: completedBytes),
                      formatBytes(bytes: totalBytes))
    }

    private var etaText: String {
        String(format: String(localized: "setup.whiskywine.eta"),
               formatRemainingTime(remainingBytes: totalBytes - completedBytes))
    }

    private func startDownload() {
        downloadTask?.cancel()
        observation?.invalidate()
        observation = nil

        downloadError = nil
        fractionProgress = 0
        completedBytes = 0
        totalBytes = 0
        downloadSpeed = 0

        guard let url = URL(string: "https://data.getwhisky.app/Wine/Libraries.tar.gz") else {
            downloadError = String(localized: "setup.whiskywine.download.failed")
            return
        }

        let task = Self.session.downloadTask(with: url) { fileURL, response, error in
            // URLSession deletes the completion-handler file when this closure
            // returns, so move it to a stable path synchronously.
            var stableURL: URL?
            var failure: String?

            if let error {
                if (error as NSError).code != NSURLErrorCancelled {
                    failure = error.localizedDescription
                }
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                failure = "HTTP \(http.statusCode)"
            } else if let fileURL {
                let destination = FileManager.default.temporaryDirectory
                    .appending(path: "WhiskyWine-\(UUID().uuidString).tar.gz")
                do {
                    try FileManager.default.moveItem(at: fileURL, to: destination)
                    stableURL = destination
                } catch {
                    failure = error.localizedDescription
                }
            } else {
                failure = String(localized: "setup.whiskywine.download.failed")
            }

            Task { @MainActor in
                self.observation?.invalidate()
                self.observation = nil

                if let failure {
                    self.downloadError = failure
                } else if let stableURL {
                    self.tarLocation = stableURL
                    self.proceed()
                }
            }
        }

        observation = task.observe(\.countOfBytesReceived) { task, _ in
            Task { @MainActor in
                let received = task.countOfBytesReceived
                let expected = task.countOfBytesExpectedToReceive

                self.completedBytes = received
                self.totalBytes = max(expected, 0)

                if self.totalBytes > 0 {
                    self.fractionProgress = min(max(Double(received) / Double(self.totalBytes), 0), 1)
                }

                let now = Date()
                let elapsed = now.timeIntervalSince(self.startTime ?? now)
                if elapsed > 0 && received > 0 {
                    self.downloadSpeed = Double(received) / elapsed
                }
            }
        }

        downloadTask = task
        startTime = Date()
        task.resume()
    }

    func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0 && downloadSpeed > 0
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        guard downloadSpeed > 0, remainingBytes > 0 else { return "" }

        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(remainingTimeInSeconds)) ?? ""
    }

    func proceed() {
        path.append(.whiskyWineInstall)
    }
}
