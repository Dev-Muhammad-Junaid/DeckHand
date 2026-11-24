//
//  PixelHandIntents.swift
//  DeckHandiOS + DeckHandWidgets (compiled into both)
//
//  The App Intents (D6). Each one builds a `RemoteCommand` (Core) and hands
//  it to `IntentDispatch`.
//
//  Reaching the Mac: the Loom connection lives in the app's process, and
//  iOS doesn't keep it up in the background, so every intent that acts on
//  the Mac sets `openAppWhenRun`. The app comes to the front and runs the
//  command on the live session at once; with no Mac connected it waits
//  (`PendingCommandQueue`, 90 s) and runs when the user picks a Mac. Widget
//  buttons and Control Center controls use the same intents.
//

import AppIntents
import Foundation
import PixelHandCore

// MARK: - Dispatch

/// What happened to a command, as Siri and Shortcuts say it.
enum IntentRunOutcome: Sendable, Equatable {
    case done
    /// No Mac is connected yet; it runs when one connects.
    case waitingForMac
    case needsPro(ProFeature)
    case keyMissing
    /// The Mac didn't confirm it (Accessibility off, or no answer).
    case notDelivered
    case connectedToOtherMac(String)
    case invalid(RemoteCommandIssue)

    var message: String {
        switch self {
        case .done: "Done."
        case .waitingForMac: "Pick your Mac in Pixel Hand. It runs as soon as it connects."
        case let .needsPro(feature): Self.proMessage(feature)
        case .keyMissing: "That deck key isn't in your deck anymore."
        case .notDelivered: "Your Mac didn't confirm it. Check that Pixel Hand has Accessibility on the Mac."
        case let .connectedToOtherMac(name): "Pixel Hand is connected to \(name). Switch Macs and try again."
        case .invalid(.emptyText): "There's no text to type."
        case .invalid(.textTooLong): "That's too much text to type at once (\(RemoteCommandLimits.maxTypedCharacters) characters at most)."
        case .invalid(.badKeyID): "That deck key isn't in your deck anymore."
        }
    }

    private static func proMessage(_ feature: ProFeature) -> String {
        switch feature {
        case .decks: "Running deck keys is part of Pixel Hand Pro."
        case .mirror: "The live mirror is part of Pixel Hand Pro."
        case .capture: "Screenshots are part of Pixel Hand Pro."
        case .multipleMacs: "Controlling more than one Mac is part of Pixel Hand Pro."
        case .sharing: "Clipboard sharing is part of Pixel Hand Pro."
        case .ai: "Ask is part of Pixel Hand Pro."
        case .trackpad, .keyboard, .mediaKeys: "This needs Pixel Hand Pro."
        }
    }
}

@MainActor
enum IntentDispatch {
    /// Set by the app at launch (`IntentBridge.start()`). `nil` in the
    /// widget extension's process, where commands are queued for the app.
    static var handler: ((PendingCommand) async -> IntentRunOutcome)?

    static func run(_ command: RemoteCommand, on mac: MacEntity? = nil) async -> IntentRunOutcome {
        if let issue = command.validationIssue { return .invalid(issue) }
        let pending = PendingCommand(command: command, macID: mac?.id, queuedAt: Date())
        if let handler { return await handler(pending) }
        // Not the app (or before it registered): check the plan from the
        // snapshot, then leave it for the app, which drains the queue when
        // it starts and whenever a Mac connects.
        let snapshot = PixelHandAppGroup.readSnapshot()
        if command.feature.tier == .pro, !snapshot.isPro { return .needsPro(command.feature) }
        PixelHandAppGroup.enqueue(pending)
        return .waitingForMac
    }
}

extension IntentRunOutcome {
    /// Turns refusals into intent errors, so Shortcuts stops a workflow
    /// that depended on the step.
    func dialogOrThrow() throws -> IntentDialog {
        switch self {
        case .done, .waitingForMac: return IntentDialog(stringLiteral: message)
        default: throw PixelHandIntentError(message: message)
        }
    }
}

struct PixelHandIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

// MARK: - Run a deck key (Pro)

struct RunDeckKeyIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Deck Key"
    static let description = IntentDescription("Runs one of your Pixel Hand deck keys on your Mac.")
    static let openAppWhenRun = true

    @Parameter(title: "Key")
    var key: DeckKeyEntity

    @Parameter(title: "Mac", description: "Only run it on this Mac.")
    var mac: MacEntity?

    init() {}

    init(key: DeckKeyEntity) {
        self.key = key
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$key)") {
            \.$mac
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // "Ask before running" keys ask here too (widgets never show them).
        if key.confirm {
            let confirmed = try await $key.requestConfirmation(for: key, dialog: "Run \(key.label) on your Mac?")
            guard confirmed else { throw PixelHandIntentError(message: "Not run.") }
        }
        let outcome = await IntentDispatch.run(.runKey(keyID: key.id), on: mac)
        return .result(dialog: try outcome.dialogOrThrow())
    }
}

// MARK: - System actions (free)

struct RunMacActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Mac Action"
    static let description = IntentDescription("Mission Control, Show Desktop, Lock Screen and other Mac-wide actions.")
    static let openAppWhenRun = true

    @Parameter(title: "Action", default: .missionControl)
    var action: SystemActionOption

    @Parameter(title: "Mac", description: "Only run it on this Mac.")
    var mac: MacEntity?

    init() {}

    init(action: SystemActionOption) {
        self.action = action
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$action) on the Mac") {
            \.$mac
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentDispatch.run(.system(action.command), on: mac)
        return .result(dialog: try outcome.dialogOrThrow())
    }
}

/// "Lock my Mac": its own intent so Siri has a phrase without a parameter.
struct LockMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Mac Screen"
    static let description = IntentDescription("Locks the screen of the Mac Pixel Hand controls.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentDispatch.run(.system(.lockScreen))
        return .result(dialog: try outcome.dialogOrThrow())
    }
}

// MARK: - Media keys (free)

struct PressMediaKeyIntent: AppIntent {
    static let title: LocalizedStringResource = "Press Media Key"
    static let description = IntentDescription("Play/pause or skip tracks on your Mac.")
    static let openAppWhenRun = true

    @Parameter(title: "Key", default: .playPause)
    var key: MediaKeyOption

    init() {}

    init(key: MediaKeyOption) {
        self.key = key
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Press \(\.$key) on the Mac")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentDispatch.run(.media(key.key))
        return .result(dialog: try outcome.dialogOrThrow())
    }
}

// MARK: - Type text (free)

struct TypeTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Type Text on Mac"
    static let description = IntentDescription("Types text into the Mac's front app, as the Pixel Hand keyboard does.")
    static let openAppWhenRun = true

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Type \(\.$text) on the Mac")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentDispatch.run(.typeText(text))
        return .result(dialog: try outcome.dialogOrThrow())
    }
}

// MARK: - Screenshot (Pro)

struct TakeMacScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Mac Screenshot"
    static let description = IntentDescription("Captures the Mac's screen and opens it in Pixel Hand.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentDispatch.run(.screenshot)
        return .result(dialog: try outcome.dialogOrThrow())
    }
}

// MARK: - Mirror (Pro)

struct SetMirrorIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or Stop Mirror"
    static let description = IntentDescription("Starts or stops the live picture of your Mac's screen.")
    static let openAppWhenRun = true

    @Parameter(title: "Mirror", default: .start)
    var mode: MirrorModeOption

    init() {}

    init(mode: MirrorModeOption) {
        self.mode = mode
    }

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$mode) the mirror")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentDispatch.run(.mirror(mode.mode))
        return .result(dialog: try outcome.dialogOrThrow())
    }
}

// MARK: - Open the trackpad (free)

struct OpenTrackpadIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Trackpad"
    static let description = IntentDescription("Opens Pixel Hand on the trackpad.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = await IntentDispatch.run(.open(.trackpad))
        return .result()
    }
}
