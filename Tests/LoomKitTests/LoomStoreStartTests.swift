//
//  LoomStoreStartTests.swift
//  LoomKit
//
//  The store's start is single-flight: callers that arrive while a start is
//  in flight join it instead of racing it, and cancelling one caller doesn't
//  cancel the start the others are waiting on.
//

@testable import Loom
@testable import LoomKit
import Foundation
import Testing

@Suite("LoomKit Store Start", .serialized)
struct LoomStoreStartTests {
    @MainActor
    @Test("Concurrent starts join one start instead of advertising twice")
    func concurrentStartsJoinOneStart() async throws {
        let store = makeStartTestStore()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        try await store.start()
                    }
                }
                try await group.waitForAll()
            }
            #expect(await isRunning(store))

            // Starting again once running is a no-op, not a second advertisement.
            try await store.start()
            #expect(await isRunning(store))
        } catch {
            await store.stop()
            throw error
        }
        await store.stop()
        #expect(await !isRunning(store))
    }

    @MainActor
    @Test("Cancelling the first caller doesn't cancel the start a later caller joined")
    func cancelledCallerDoesNotCancelStart() async throws {
        let store = makeStartTestStore()
        do {
            let first = Task {
                try await store.start()
            }
            first.cancel()
            try await store.start()
            // The cancelled caller still sees the start succeed.
            try await first.value
            #expect(await isRunning(store))
        } catch {
            await store.stop()
            throw error
        }
        await store.stop()
    }

    @MainActor
    @Test("The store can start again after a stop")
    func restartAfterStop() async throws {
        let store = makeStartTestStore()
        do {
            try await store.start()
            await store.stop()
            #expect(await !isRunning(store))
            try await store.start()
            #expect(await isRunning(store))
        } catch {
            await store.stop()
            throw error
        }
        await store.stop()
    }
}

@MainActor
private func makeStartTestStore() -> LoomStore {
    let serviceType = "_lkst\(UUID().uuidString.prefix(6).lowercased())._tcp"
    let configuration = LoomContainerConfiguration(
        serviceType: serviceType,
        serviceName: "Start Test Host",
        deviceIDSuiteName: "com.ethanlipnik.loom.tests.loomkit-start.\(UUID().uuidString)",
        enablePeerToPeer: false
    )
    let identityManager = LoomIdentityManager(
        service: "com.ethanlipnik.loom.tests.loomkit-start-node.\(UUID().uuidString)",
        account: "p256-signing",
        synchronizable: false
    )
    let node = LoomNode(
        configuration: LoomNetworkConfiguration(
            serviceType: serviceType,
            enablePeerToPeer: false,
            enabledDirectTransports: [.tcp]
        ),
        identityManager: identityManager
    )
    return LoomStore(
        configuration: configuration,
        deviceID: UUID(),
        node: node,
        trustStore: LoomTrustStore(
            suiteName: "com.ethanlipnik.loom.tests.loomkit-start-trust.\(UUID().uuidString)"
        ),
        cloudKitManager: nil,
        peerProvider: nil,
        peerManager: nil,
        signalingClient: nil,
        connectionCoordinator: LoomConnectionCoordinator(node: node)
    )
}

private func isRunning(_ store: LoomStore) async -> Bool {
    let stream = await store.makeSnapshotStream()
    for await snapshot in stream {
        return snapshot.isRunning
    }
    return false
}
