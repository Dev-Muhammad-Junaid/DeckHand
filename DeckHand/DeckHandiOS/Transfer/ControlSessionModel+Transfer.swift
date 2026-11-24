//
//  ControlSessionModel+Transfer.swift
//  DeckHandiOS – Transfer
//
//  The Sharing lane's part of the session model (S1): hands the focused
//  Mac to `TransferCenter` once access is granted, for as long as the
//  session runs. Started from `run(settings:)` (one announced task);
//  `sharing.transferStatus` arrives through `handleSharingMessage`.
//

import Foundation

extension ControlSessionModel {
    /// Runs for the session; cancelled with it.
    func runTransfers() async {
        while lastAuthStatus != "granted" {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
        let connection = self.connection
        let deviceID = connection.peer.deviceID
        await withTaskCancellationHandler {
            await TransferCenter.shared.run(
                connection: connection,
                macName: connection.peer.name,
                isPaired: { [weak self] in
                    // The Mac said so this session, or it is on this
                    // device's paired list (trust keyed on its identity).
                    (self?.pairedThisSession ?? false)
                        || PairedMacsStore.shared.macs.contains { $0.deviceID == deviceID }
                }
            )
        } onCancel: {
            Task { @MainActor in TransferCenter.shared.detach(connectionID: connection.id) }
        }
    }
}
