@testable import LoomSharedRuntime
import Darwin
import Foundation
import Testing

@Suite("LoomHostSocketConnection")
struct LoomHostSocketConnectionTests {
    @Test("Read loop closes connection when buffered frame exceeds maximum size")
    func closesConnectionWhenBufferedFrameIsTooLarge() async throws {
        var sockets = [Int32](repeating: 0, count: 2)
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        defer {
            Darwin.close(sockets[1])
        }

        let connectionClosed = AsyncStream<Void> { continuation in
            let connection = LoomHostSocketConnection(
                fileDescriptor: sockets[0],
                onFrame: { _ in },
                onClosed: {
                    continuation.yield(())
                    continuation.finish()
                }
            )
            continuation.onTermination = { _ in
                Task {
                    await connection.close()
                }
            }
            Task {
                await connection.startReading()
            }
        }

        var oversizedFrame = Data(
            repeating: 0x61,
            count: 1_048_577
        )
        try oversizedFrame.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var bytesSent = 0
            while bytesSent < rawBuffer.count {
                let written = Darwin.write(
                    sockets[1],
                    baseAddress.advanced(by: bytesSent),
                    rawBuffer.count - bytesSent
                )
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                bytesSent += written
            }
        }
        oversizedFrame.removeAll(keepingCapacity: false)

        let didClose = await nextValue(from: connectionClosed, timeout: .seconds(2))
        #expect(didClose != nil)
    }

    @Test("Frames arrive while more read loops wait than there are cores")
    func framesArriveWithMoreWaitingReadLoopsThanCores() async throws {
        // Every connection's read loop waits in `read` between frames. When
        // those waits held Swift concurrency threads, this many of them left
        // none to run anything else, this test's timeout included, and the
        // whole test process stalled.
        let pairCount = ProcessInfo.processInfo.activeProcessorCount + 1
        let (arrivals, arrival) = AsyncStream<Int>.makeStream()
        var connections: [LoomHostSocketConnection] = []
        var senders: [LoomHostSocketConnection] = []

        for index in 0 ..< pairCount {
            var sockets = [Int32](repeating: 0, count: 2)
            try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
            let sender = LoomHostSocketConnection(
                fileDescriptor: sockets[0],
                onFrame: { _ in },
                onClosed: {}
            )
            let receiver = LoomHostSocketConnection(
                fileDescriptor: sockets[1],
                onFrame: { _ in arrival.yield(index) },
                onClosed: {}
            )
            await sender.startReading()
            await receiver.startReading()
            senders.append(sender)
            connections += [sender, receiver]
        }

        for sender in senders {
            try await sender.send(
                LoomHostIPCFrame(requestID: nil, message: .refreshPeers(clientID: UUID()))
            )
        }

        let arrived = await withTaskGroup(of: Set<Int>?.self) { group in
            group.addTask {
                var arrived = Set<Int>()
                for await index in arrivals {
                    arrived.insert(index)
                    if arrived.count == pairCount {
                        break
                    }
                }
                return arrived
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        #expect(arrived?.count == pairCount)

        for connection in connections {
            await connection.close()
        }
    }
}

private func nextValue<Element: Sendable>(
    from stream: AsyncStream<Element>,
    timeout: Duration
) async -> Element? {
    await withTaskGroup(of: Element?.self) { group in
        group.addTask {
            for await value in stream {
                return value
            }
            return nil
        }

        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
