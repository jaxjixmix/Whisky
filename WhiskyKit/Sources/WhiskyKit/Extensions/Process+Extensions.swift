//
//  Process+Extensions.swift
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

public enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

/// Buffers pipe bytes until a newline, so a read that splits a line (or a
/// multi-byte character) never produces a partial message or a lost byte.
private final class PipeLineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)

        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = decode(lineData) {
                lines.append(line)
            }
        }
        return lines
    }

    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard !buffer.isEmpty else { return nil }
        let lineData = buffer
        buffer.removeAll(keepingCapacity: false)
        return decode(lineData)
    }

    private func decode(_ data: Data) -> String? {
        var data = data
        if data.last == 0x0D {
            data.removeLast()
        }
        guard !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

public extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let stream = makeStream(name: name, fileHandle: fileHandle)
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        try run()
        return stream
    }

    private func makeStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        standardOutput = pipe
        standardError = errorPipe

        return AsyncStream<ProcessOutput> { continuation in
            continuation.onTermination = { termination in
                switch termination {
                case .finished:
                    break
                case .cancelled:
                    guard self.isRunning else { return }
                    self.terminate()
                @unknown default:
                    break
                }
            }

            continuation.yield(.started(self))

            let stdoutBuffer = PipeLineBuffer()
            let stderrBuffer = PipeLineBuffer()

            let emitMessage: @Sendable (String) -> Void = { line in
                continuation.yield(.message(line))
                Logger.wineKit.info("\(line, privacy: .public)")
                fileHandle?.write(line: line + "\n")
            }
            let emitError: @Sendable (String) -> Void = { line in
                continuation.yield(.error(line))
                Logger.wineKit.warning("\(line, privacy: .public)")
                fileHandle?.write(line: line + "\n")
            }

            // A readability handler stays armed after EOF and fires forever on
            // an always-readable closed pipe, which pegs a core (issue #1010).
            // Disarm it on the first empty read; the final bytes are drained in
            // the termination handler.
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if let line = stdoutBuffer.flush() {
                        emitMessage(line)
                    }
                    return
                }
                for line in stdoutBuffer.append(data) {
                    emitMessage(line)
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if let line = stderrBuffer.flush() {
                        emitError(line)
                    }
                    return
                }
                for line in stderrBuffer.append(data) {
                    emitError(line)
                }
            }

            terminationHandler = { (process: Process) in
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                if let remaining = try? pipe.fileHandleForReading.readToEnd(), !remaining.isEmpty {
                    for line in stdoutBuffer.append(remaining) {
                        emitMessage(line)
                    }
                }
                if let line = stdoutBuffer.flush() {
                    emitMessage(line)
                }

                if let remaining = try? errorPipe.fileHandleForReading.readToEnd(), !remaining.isEmpty {
                    for line in stderrBuffer.append(remaining) {
                        emitError(line)
                    }
                }
                if let line = stderrBuffer.flush() {
                    emitError(line)
                }

                try? fileHandle?.close()

                process.logTermination(name: name)
                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    private func logTermination(name: String) {
        if terminationStatus == 0 {
            Logger.wineKit.info(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        } else {
            Logger.wineKit.warning(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        }
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments = arguments {
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
}
