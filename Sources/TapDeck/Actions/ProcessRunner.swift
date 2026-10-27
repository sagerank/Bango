import Foundation

struct ProcessResult {
    var status: Int32
    var output: String
    var error: String
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    /// Returns true the first time it is called.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Runs a program without a shell and waits for it. The program is stopped after `timeout` seconds.
enum ProcessRunner {
    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 15,
        captureOutput: Bool = true
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = captureOutput ? outPipe : FileHandle.nullDevice
            process.standardError = errPipe

            let once = OnceFlag()
            process.terminationHandler = { finished in
                let out = captureOutput ? outPipe.fileHandleForReading.readDataToEndOfFile() : Data()
                let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                guard once.claim() else { return }
                continuation.resume(returning: ProcessResult(
                    status: finished.terminationStatus,
                    output: String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    error: String(data: err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                ))
            }

            do {
                try process.run()
            } catch {
                if once.claim() { continuation.resume(throwing: error) }
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
