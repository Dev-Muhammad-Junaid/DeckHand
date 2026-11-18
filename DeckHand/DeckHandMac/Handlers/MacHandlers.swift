//
//  MacHandlers.swift
//  DeckHandMac
//
//  The one place the Mac's domain handlers are registered. `ControlReceiver`
//  owns the connection lifecycle and the message loop; every decoded,
//  validated message goes through `router`, which hands it to the handler
//  for its domain. Each lane owns its handler file (see
//  DeckHand/Integration/LANES.md).
//

import LoomKit

@MainActor
final class MacHandlers {
    let input = InputHandler()
    let system = SystemHandler()
    let apps = AppsHandler()
    let deck = DeckHandler()
    let mirror = MirrorHandler()
    let capture = CaptureHandler()
    let pairing = PairingHandler()
    let session = SessionHandler()

    let router: ControlRouter<LoomConnectionHandle>

    init() {
        router = ControlRouter(
            input: input,
            system: system,
            apps: apps,
            deck: deck,
            mirror: mirror,
            capture: capture,
            pairing: pairing,
            session: session
        )
        // A tracked run is dispatched as the message its action stands for,
        // through the same handlers as everything else.
        deck.router = router
    }
}
