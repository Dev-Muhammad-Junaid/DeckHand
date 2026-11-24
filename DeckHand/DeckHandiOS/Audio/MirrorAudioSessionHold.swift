//
//  MirrorAudioSessionHold.swift
//  DeckHandiOS
//
//  UX-041: Picture in Picture needs the `.playback` audio session (and the
//  `audio` background mode) whether or not the Mac's sound plays. While PiP
//  could start, the session is held active here, and `MirrorAudioPlayer`
//  leaves it active when its own playback stops. `.mixWithOthers`, like the
//  player: holding it never interrupts this device's own sound.
//

import AVFoundation
import Foundation
import os

final class MirrorAudioSessionHold: @unchecked Sendable {
    static let shared = MirrorAudioSessionHold()

    private let lock = OSAllocatedUnfairLock(initialState: false)

    /// PiP holds the session.
    var isHeld: Bool { lock.withLock { $0 } }

    /// Holds or releases the session. Releasing deactivates it unless
    /// `stillPlaying` (the Mac's sound is on).
    func setHeld(_ held: Bool, stillPlaying: Bool) {
        let changed = lock.withLock { state -> Bool in
            guard state != held else { return false }
            state = held
            return true
        }
        guard changed else { return }
        let session = AVAudioSession.sharedInstance()
        if held {
            do {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                DeckHandLog.connection.error("PiP: couldn't set up the playback audio session: \(error.localizedDescription, privacy: .public)")
            }
        } else if !stillPlaying {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
