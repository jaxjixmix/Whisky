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
    /// A child that never writes a newline must not grow memory without bound.
    private static let maxBufferedBytes = 1_000_000
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

        if buffer.count > Self.maxBufferedBytes {
            if let line = decode(buffer) {
                lines.append(line)
            }
            buffer.removeAll(keepingCapacity: true)
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
        return String(bytes: data, encoding: .utf8)
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

            self.installLineHandler(on: pipe, buffer: stdoutBuffer, emit: emitMessage)
            self.installLineHandler(on: errorPipe, buffer: stderrBuffer, emit: emitError)

            terminationHandler = { (process: Process) in
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                self.drain(pipe, buffer: stdoutBuffer, emit: emitMessage)
                self.drain(errorPipe, buffer: stderrBuffer, emit: emitError)

                try? fileHandle?.close()

                process.logTermination(name: name)
                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    /// Read pipe bytes until a newline and emit whole lines. The handler
    /// disarms itself at EOF; a permanently-readable closed pipe otherwise
    /// fires forever (issue #1010).
    private func installLineHandler(
        on pipe: Pipe,
        buffer: PipeLineBuffer,
        emit: @escaping @Sendable (String) -> Void
    ) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                if let line = buffer.flush() {
                    emit(line)
                }
                return
            }
            for line in buffer.append(data) {
                emit(line)
            }
        }
    }

    /// Consume anything the readability handler did not see before exit.
    private func drain(_ pipe: Pipe, buffer: PipeLineBuffer, emit: @Sendable (String) -> Void) {
        if let remaining = try? pipe.fileHandleForReading.readToEnd(), !remaining.isEmpty {
            for line in buffer.append(remaining) {
                emit(line)
            }
        }
        if let line = buffer.flush() {
            emit(line)
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
