//
//  MacShortcutRunner.swift
//  DeckHandMac
//
//  Runs `Action.macShortcut`: `/usr/bin/shortcuts run <name>` as a child
//  process (never through a shell), terminated after
//  `MacShortcutRun.timeout`. Core's `MacShortcutRun` builds the arguments
//  and turns the ending into a receipt.
//

import Foundation

enum MacShortcutRunner {
    /// Runs the shortcut called `name` and reports how it ended. Doesn't
    /// block the caller's actor: the process is waited on from its
    /// termination handler.
    static func run(name: String) async -> MacShortcutRun.Ending {
        guard let arguments = MacShortcutRun.arguments(name: name),
              FileManager.default.isExecutableFile(atPath: MacShortcutRun.executablePath) else {
            return .couldNotStart
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: MacShortcutRun.executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let ending = EndingBox()
        let running = ProcessBox(process)
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                ending.finish(.exited(status: finished.terminationStatus), continuation)
            }
            do {
                try process.run()
            } catch {
                ending.finish(.couldNotStart, continuation)
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + MacShortcutRun.timeout) {
                guard running.process.isRunning else { return }
                running.process.terminate()
                ending.finish(.timedOut, continuation)
            }
        }
    }

    /// `Process` isn't `Sendable`; the timeout only reads `isRunning` and
    /// calls `terminate()`, which are safe from any thread.
    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
    }

    /// Resumes the continuation once, whichever of exit, timeout or a
    /// failed start comes first.
    private final class EndingBox: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func finish(_ ending: MacShortcutRun.Ending, _ continuation: CheckedContinuation<MacShortcutRun.Ending, Never>) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { continuation.resume(returning: ending) }
        }
    }
}
