import Foundation
@testable import WhiskyKit

@main
struct SelfTest {
    static func main() async {
        var failures = 0

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() {
                print("PASS: \(message)")
            } else {
                failures += 1
                print("FAIL: \(message)")
            }
        }

        let lines = await streamedMessages(
            arguments: ["-c", "printf 'one\\ntwo\\npart'; sleep 0.05; printf 'ial\\n'"]
        )
        check(lines == ["one", "two", "partial"], "lines are buffered across reads: \(lines)")

        let eofCount = await messageCountBeforeExit(
            arguments: ["-c", "printf 'done\\n'; sleep 1"],
            waitNanoseconds: 300_000_000
        )
        check(eofCount == 1, "closed pipe stops producing messages: \(eofCount)")

        check(cappedLogStaysBounded(), "log is capped and leaves a truncation marker")

        if failures > 0 {
            print("\(failures) self-test(s) failed")
            exit(1)
        }
        print("All WhiskyKit self-tests passed")
    }

    static func streamedMessages(arguments: [String]) async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        guard let stream = try? process.runStream(name: "self-test", fileHandle: nil) else {
            return []
        }

        var messages: [String] = []
        for await output in stream {
            if case .message(let message) = output {
                messages.append(message)
            }
        }
        return messages
    }

    static func cappedLogStaysBounded() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "whisky-log-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try Data().write(to: url)
            let handle = try FileHandle(forWritingTo: url)
            let line = String(repeating: "a", count: 100_000) + "\n"
            let writes = Int(FileHandle.maxLogSize / 100_000) + 2
            for _ in 0..<writes {
                handle.write(line: line)
            }
            try handle.close()

            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let contents = try String(contentsOf: url, encoding: .utf8)
            return size <= Int(FileHandle.maxLogSize) + line.utf8.count
                && contents.contains("log truncated")
                && contents.hasSuffix(line)
        } catch {
            print("log cap test error: \(error)")
            return false
        }
    }

    static func messageCountBeforeExit(arguments: [String], waitNanoseconds: UInt64) async -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        guard let stream = try? process.runStream(name: "self-test-eof", fileHandle: nil) else {
            return -1
        }

        let counter = Task { () -> Int in
            var count = 0
            for await output in stream {
                if case .message = output {
                    count += 1
                }
            }
            return count
        }
        try? await Task.sleep(nanoseconds: waitNanoseconds)
        counter.cancel()
        process.terminate()
        return await counter.value
    }
}
