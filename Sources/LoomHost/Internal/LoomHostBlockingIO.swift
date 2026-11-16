//
//  LoomHostBlockingIO.swift
//  LoomHost
//

import Foundation

#if os(macOS)
import Darwin

/// Runs blocking socket calls on a dispatch queue instead of a Swift
/// concurrency thread.
///
/// The cooperative pool has one thread per core and never grows, so a few
/// tasks parked in `accept` or `read` can leave no thread to run the code
/// that would wake them, and every task in the process stops. Dispatch adds
/// a thread when one of its own blocks.
package struct LoomHostBlockingIO: Sendable {
    private let queue: DispatchQueue

    package init(label: String) {
        queue = DispatchQueue(label: label)
    }

    /// Returns the call's result and the `errno` it left, read on the thread
    /// that made the call.
    package func perform<T: Sendable>(
        _ call: @escaping @Sendable () -> T
    ) async -> (result: T, errno: Int32) {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = call()
                continuation.resume(returning: (result, Darwin.errno))
            }
        }
    }
}
#endif
