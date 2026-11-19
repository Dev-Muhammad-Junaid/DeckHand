//
//  ControlSessionModel+Audio.swift
//  DeckHandiOS
//
//  S17, the Mac's sound while mirroring (owned by the mirror lane; the
//  player is `mirrorAudio`, under `// MARK: Mirror` in ControlSessionModel):
//
//  - wanted = the mirror is open, Settings › Live mirror › "Play the Mac's
//    sound" is on and Pixel Hand is in front;
//  - `syncMirrorAudio()` tells the Mac (`mirror.audio(enabled:)`) and the
//    player whenever that changes: the mirror opens or closes or stops on
//    the Mac, the setting changes, the app goes to the background or
//    comes back;
//  - `mirror.audioError` (no capture on the Mac) stops the player and
//    shows a passing notice over the mirror; the next change retries.
//
//  The audio stream's own reader runs next to the mirror's
//  (`runMirrorReceiver` starts `runMirrorAudio`).
//

import LoomKit
import SwiftUI
import UIKit

extension ControlSessionModel {

    /// Reads the Mac's audio streams and follows the app going to the
    /// background and back, until the session ends. Then stops playback.
    func runMirrorAudio() async {
        let center = NotificationCenter.default
        let observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncMirrorAudio(appActive: false) }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncMirrorAudio(appActive: true) }
            },
        ]
        defer {
            observers.forEach(center.removeObserver)
            // Disconnect: silence at once (the Mac stops on its side).
            mirrorAudio.setWanted(false)
        }
        await MirrorAudioReceiver().run(connection: connection, sink: mirrorAudio)
    }

    /// Whether the Mac's sound should play now.
    func mirrorAudioWanted(appActive: Bool) -> Bool {
        isMirrorActive && appActive && (mirrorSettings?.mirrorPlaysMacAudio ?? false)
    }

    /// Brings the Mac and the player in line with `mirrorAudioWanted`.
    func syncMirrorAudio(appActive: Bool? = nil) {
        let active = appActive ?? (UIApplication.shared.applicationState != .background)
        let wanted = mirrorAudioWanted(appActive: active)
        guard mirrorAudio.setWanted(wanted) else { return }
        let connection = connection
        Task { try? await connection.send(.mirror(.audio(enabled: wanted))) }
    }

    /// `mirror.audioError`: the Mac couldn't capture or send its sound.
    /// The mirror carries on.
    func handleMirrorAudioError(_ message: String) {
        DeckHandLog.connection.error("Mirror audio: \(message, privacy: .public)")
        mirrorAudio.setWanted(false)
        if isMirrorActive {
            showMirrorNotice(message)
        }
    }
}
