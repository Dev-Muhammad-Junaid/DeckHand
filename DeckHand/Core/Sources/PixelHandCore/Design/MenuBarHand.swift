//
//  MenuBarHand.swift
//  PixelHandCore – Design
//
//  The Mac's menu-bar hand as data (`06-Pixel-Identity.md` §8, UX-019):
//  which state the status item shows, and which dots each state lights.
//  The Mac draws these dots into a template image; keeping the rule here
//  lets it be tested on Linux.
//
//  The canvas is the icon's 17 × 18 dot hand with two rows of headroom for
//  the tap rays: 17 × 20 dots, one point each.
//

import Foundation

/// What the menu-bar hand says, most urgent first.
public enum MenuBarHandState: String, Sendable, Hashable, CaseIterable {
    /// Starting, or failed to start: the whole hand at 50 %.
    case notReady
    /// A device is asking to connect: the fingertip blinks at 1 Hz.
    case asking
    /// This Mac is locked while a device is connected: a padlock in the palm.
    case locked
    /// Text or a file just arrived: a 3-dot beam runs along the cuff.
    case receiving
    /// A device is driving the pointer or keys right now: fill and tap rays.
    case active
    /// A device is connected and idle: fill dots on.
    case connected
    /// Ready, nothing connected: outline dots.
    case ready

    /// The status item's accessibility description.
    public var accessibilityDescription: String {
        switch self {
        case .notReady: "Pixel Hand, not ready"
        case .asking: "Pixel Hand, a device is asking to connect"
        case .locked: "Pixel Hand, this Mac is locked"
        case .receiving: "Pixel Hand, receiving"
        case .active: "Pixel Hand, being controlled"
        case .connected: "Pixel Hand, device connected"
        case .ready: "Pixel Hand"
        }
    }

    /// Whether the state animates (and so needs a timer). Reduce Motion
    /// holds the first frame.
    public var animates: Bool { self == .asking || self == .receiving }

    /// The inputs the status item knows about.
    public struct Inputs: Sendable, Hashable {
        public var isRunning: Bool
        public var failedToStart: Bool
        public var pendingRequests: Int
        public var liveConnections: Int
        public var isLocked: Bool
        /// Seconds since the last input from a remote; `nil` if none yet.
        public var secondsSinceInput: TimeInterval?
        /// Seconds since the last text or file arrived; `nil` if none yet.
        public var secondsSinceReceive: TimeInterval?

        public init(
            isRunning: Bool,
            failedToStart: Bool = false,
            pendingRequests: Int = 0,
            liveConnections: Int = 0,
            isLocked: Bool = false,
            secondsSinceInput: TimeInterval? = nil,
            secondsSinceReceive: TimeInterval? = nil
        ) {
            self.isRunning = isRunning
            self.failedToStart = failedToStart
            self.pendingRequests = pendingRequests
            self.liveConnections = liveConnections
            self.isLocked = isLocked
            self.secondsSinceInput = secondsSinceInput
            self.secondsSinceReceive = secondsSinceReceive
        }
    }

    /// How long "being controlled" lasts after the last input.
    public static let activeHold: TimeInterval = 2
    /// How long the receive beam runs after something arrives.
    public static let receiveHold: TimeInterval = 1.5

    /// The one state to show for `inputs`.
    public static func resolve(_ inputs: Inputs) -> MenuBarHandState {
        if inputs.failedToStart || !inputs.isRunning { return .notReady }
        if inputs.pendingRequests > 0 { return .asking }
        guard inputs.liveConnections > 0 else { return .ready }
        if inputs.isLocked { return .locked }
        if let age = inputs.secondsSinceReceive, age >= 0, age < receiveHold { return .receiving }
        if let age = inputs.secondsSinceInput, age >= 0, age < activeHold { return .active }
        return .connected
    }
}

/// One dot of the menu-bar hand.
public struct MenuBarDot: Sendable, Hashable {
    public let x: Int
    public let y: Int
    /// Template alpha, 0…1.
    public let alpha: Double

    public init(x: Int, y: Int, alpha: Double) {
        self.x = x
        self.y = y
        self.alpha = alpha
    }
}

public enum MenuBarHand {
    /// The icon's hand: `X` outline, `o` fill. 17 × 18. Same art as the
    /// apps' `PixelArt.hand`.
    public static let handRows: [String] = [
        ".....XX..........",
        "....XooX.........",
        "....XooX.........",
        "....XooX.........",
        "....XooX.........",
        "....XooXXX.XX....",
        "....XooXooXooXX..",
        "....XooXooXooXoX.",
        ".XX.XooXooXooXoX.",
        "XooXXooXooXooXoX.",
        "XoooXooooooooooX.",
        ".XooXooooooooooX.",
        "..XoooooooooooX..",
        "..XoooooooooooX..",
        "...XooooooooooX..",
        "....XooooooooX...",
        "....XooooooooX...",
        "....XXXXXXXXXX...",
    ]

    public static let width = 17
    /// Rows above the hand for the tap rays.
    public static let headroom = 2
    public static let height = 18 + headroom

    /// Tap rays (canvas coordinates): straight up from the fingertip and
    /// one out to each side.
    public static let rays: [GlyphPoint] = [
        GlyphPoint(x: 5, y: 0), GlyphPoint(x: 6, y: 0), GlyphPoint(x: 3, y: 1), GlyphPoint(x: 8, y: 1),
    ]

    /// The fingertip's fill (canvas coordinates) that blinks while a device asks.
    public static let fingertip: [GlyphPoint] = [
        GlyphPoint(x: 5, y: 3), GlyphPoint(x: 6, y: 3), GlyphPoint(x: 5, y: 4), GlyphPoint(x: 6, y: 4),
    ]

    /// A 5 × 6 padlock in the palm (canvas coordinates).
    public static let padlock: [GlyphPoint] = {
        let rows = [
            ".XXX.",
            "X...X",
            "XXXXX",
            "XX.XX",
            "XX.XX",
            "XXXXX",
        ]
        var points: [GlyphPoint] = []
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() where cell == "X" {
                points.append(GlyphPoint(x: 7 + x, y: 12 + y))
            }
        }
        return points
    }()

    /// The cuff row (canvas y) the receive beam runs along, and its columns.
    public static let cuffRow = 19
    public static let cuffColumns = 4...13
    /// Dots in the receive beam.
    public static let beamLength = 3
    /// Frames in one beam pass (the cuff's width).
    public static var beamFrames: Int { cuffColumns.count }

    /// Template alpha for fill dots in the connected states: lighter than
    /// the outline so the knuckle lines still read.
    public static let fillAlpha = 0.45
    /// The whole hand's alpha when not ready.
    public static let dimAlpha = 0.5

    /// What a hand cell is.
    enum Cell { case off, outline, fill }

    static func cell(_ x: Int, _ y: Int) -> Cell {
        let handY = y - headroom
        guard handY >= 0, handY < handRows.count, x >= 0, x < width else { return .off }
        let row = Array(handRows[handY])
        guard x < row.count else { return .off }
        switch row[x] {
        case "X": return .outline
        case "o": return .fill
        default: return .off
        }
    }

    /// The lit dots for `state`. `frame` advances animated states: the
    /// fingertip is lit on even frames (two frames a second gives 1 Hz),
    /// and the beam moves one column per frame. Pass 0 under Reduce Motion:
    /// a steady fingertip and a still beam.
    public static func dots(for state: MenuBarHandState, frame: Int = 0) -> [MenuBarDot] {
        var alpha: [GlyphPoint: Double] = [:]
        let padlock = Set(Self.padlock)

        for y in 0..<height {
            for x in 0..<width {
                let point = GlyphPoint(x: x, y: y)
                switch cell(x, y) {
                case .off:
                    break
                case .outline:
                    alpha[point] = 1
                case .fill:
                    switch state {
                    case .connected, .active, .receiving:
                        alpha[point] = fillAlpha
                    case .locked:
                        // The palm stays empty around the padlock.
                        if padlock.contains(point) { alpha[point] = 1 }
                    case .notReady, .asking, .ready:
                        break
                    }
                }
            }
        }

        switch state {
        case .notReady:
            for (point, value) in alpha { alpha[point] = value * dimAlpha }
        case .asking:
            if frame % 2 == 0 {
                for point in fingertip { alpha[point] = 1 }
            }
        case .active:
            for point in rays { alpha[point] = 1 }
        case .receiving:
            // The cuff turns into the beam: dim, with three bright dots moving.
            let columns = Array(cuffColumns)
            for x in columns { alpha[GlyphPoint(x: x, y: cuffRow)] = 0.3 }
            let start = ((frame % columns.count) + columns.count) % columns.count
            for i in 0..<beamLength {
                let x = columns[(start + i) % columns.count]
                alpha[GlyphPoint(x: x, y: cuffRow)] = 1
            }
        case .locked, .connected, .ready:
            break
        }

        return alpha
            .filter { $0.value > 0 }
            .map { MenuBarDot(x: $0.key.x, y: $0.key.y, alpha: $0.value) }
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }
}
