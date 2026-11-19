//
//  PixelGlyphs.swift
//  PixelHandCore
//
//  The 40 Pixel Hand glyphs on one 9 × 9 dot grid, ported cell for cell
//  from the design board (`Product/Design/board/pixel.js`, `G`). `#` is a
//  dot, `*` the one lit accent dot (the action point), `.` an unlit cell.
//  Spec: `Product/Design/06-Pixel-Identity.md` §1.
//

/// The glyph set. App views draw these with a `Canvas` at an allowed pitch
/// (`PixelPitch.glyph`); nothing here depends on SwiftUI.
public enum PixelGlyphs {
    /// Pointer.
    public static let pointer = GlyphBitmap(
        name: "pointer",
        label: "Pointer",
        pattern: [
            "#........",
            "##.......",
            "#.#......",
            "#..#.....",
            "#...#....",
            "#....#...",
            "#.####...",
            "##.......",
            "#........",
        ]
    )

    /// Click.
    public static let click = GlyphBitmap(
        name: "click",
        label: "Click",
        pattern: [
            "....#....",
            ".........",
            "..#####..",
            "..#...#..",
            "#.#.*.#.#",
            "..#...#..",
            "..#####..",
            ".........",
            "....#....",
        ]
    )

    /// Screen.
    public static let screen = GlyphBitmap(
        name: "screen",
        label: "Screen",
        pattern: [
            ".........",
            "#########",
            "#.......#",
            "#.......#",
            "#.......#",
            "#.......#",
            "#########",
            "....#....",
            "..#####..",
        ]
    )

    /// Deck.
    public static let deck = GlyphBitmap(
        name: "deck",
        label: "Deck",
        pattern: [
            ".........",
            ".###.###.",
            ".#.#.#.#.",
            ".###.###.",
            ".........",
            ".###.###.",
            ".#.#.#*#.",
            ".###.###.",
            ".........",
        ]
    )

    /// Keyboard.
    public static let keyboard = GlyphBitmap(
        name: "keyboard",
        label: "Keyboard",
        pattern: [
            ".........",
            "#########",
            "#.......#",
            "#.#.#.#.#",
            "#.......#",
            "#.#####.#",
            "#.......#",
            "#########",
            ".........",
        ]
    )

    /// Capture.
    public static let capture = GlyphBitmap(
        name: "capture",
        label: "Capture",
        pattern: [
            "##.....##",
            "#.......#",
            ".........",
            "...###...",
            "...#*#...",
            "...###...",
            ".........",
            "#.......#",
            "##.....##",
        ]
    )

    /// Mission Control.
    public static let missionControl = GlyphBitmap(
        name: "mission",
        label: "Mission Control",
        pattern: [
            ".........",
            "###...###",
            "#.#...#.#",
            "###...###",
            ".........",
            "..#####..",
            "..#...#..",
            "..#####..",
            ".........",
        ]
    )

    /// Show Desktop.
    public static let showDesktop = GlyphBitmap(
        name: "desktop",
        label: "Show Desktop",
        pattern: [
            ".........",
            "#########",
            "#.......#",
            "##.....##",
            "##.....##",
            "#.......#",
            "#########",
            "....#....",
            "..#####..",
        ]
    )

    /// Play.
    public static let play = GlyphBitmap(
        name: "play",
        label: "Play",
        pattern: [
            "..#......",
            "..##.....",
            "..###....",
            "..####...",
            "..#####..",
            "..####...",
            "..###....",
            "..##.....",
            "..#......",
        ],
        isSolid: true
    )

    /// Pause.
    public static let pause = GlyphBitmap(
        name: "pause",
        label: "Pause",
        pattern: [
            ".........",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".##...##.",
            ".........",
        ],
        isSolid: true
    )

    /// Build.
    public static let build = GlyphBitmap(
        name: "build",
        label: "Build",
        pattern: [
            ".######..",
            ".#.....#.",
            ".######..",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            "....*....",
        ]
    )

    /// Run.
    public static let run = GlyphBitmap(
        name: "run",
        label: "Run",
        pattern: [
            ".#.......",
            ".##......",
            ".#.#.....",
            ".#..#....",
            ".#...*...",
            ".#..#....",
            ".#.#.....",
            ".##......",
            ".#.......",
        ]
    )

    /// Stop.
    public static let stop = GlyphBitmap(
        name: "stop",
        label: "Stop",
        pattern: [
            ".........",
            ".#######.",
            ".#.....#.",
            ".#.....#.",
            ".#.....#.",
            ".#.....#.",
            ".#.....#.",
            ".#######.",
            ".........",
        ]
    )

    /// Test.
    public static let test = GlyphBitmap(
        name: "test",
        label: "Test",
        pattern: [
            ".........",
            ".........",
            "........#",
            ".......#.",
            "#.....#..",
            ".#...#...",
            "..#.#....",
            "...*.....",
            ".........",
        ]
    )

    /// Find.
    public static let find = GlyphBitmap(
        name: "search",
        label: "Find",
        pattern: [
            "..###....",
            ".#...#...",
            "#.....#..",
            "#.....#..",
            "#.....#..",
            ".#...#...",
            "..###.#..",
            ".......#.",
            "........*",
        ]
    )

    /// Console.
    public static let console = GlyphBitmap(
        name: "terminal",
        label: "Console",
        pattern: [
            ".........",
            "#########",
            "#.......#",
            "#.#.....#",
            "#..#....#",
            "#.#.##*.#",
            "#.......#",
            "#########",
            ".........",
        ]
    )

    /// Lock.
    public static let lock = GlyphBitmap(
        name: "lock",
        label: "Lock",
        pattern: [
            "...###...",
            "..#...#..",
            "..#...#..",
            ".#######.",
            ".#.....#.",
            ".#..*..#.",
            ".#..#..#.",
            ".#.....#.",
            ".#######.",
        ]
    )

    /// Send.
    public static let send = GlyphBitmap(
        name: "send",
        label: "Send",
        pattern: [
            "....*....",
            "...#.#...",
            "..#.#.#..",
            ".#..#..#.",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
        ]
    )

    /// Share.
    public static let share = GlyphBitmap(
        name: "share",
        label: "Share",
        pattern: [
            "....*....",
            "...###...",
            "..#.#.#..",
            "....#....",
            "#...#...#",
            "#.......#",
            "#.......#",
            "#########",
            ".........",
        ]
    )

    /// Ask.
    public static let ask = GlyphBitmap(
        name: "ask",
        label: "Ask",
        pattern: [
            ".........",
            ".#..#..#.",
            ".........",
            ".........",
            ".#..*..#.",
            ".........",
            ".........",
            ".#..#..#.",
            ".........",
        ]
    )

    /// Mac.
    public static let mac = GlyphBitmap(
        name: "laptop",
        label: "Mac",
        pattern: [
            ".........",
            ".#######.",
            ".#.....#.",
            ".#.....#.",
            ".#.....#.",
            ".#######.",
            "#########",
            ".........",
            ".........",
        ]
    )

    /// iPhone.
    public static let iPhone = GlyphBitmap(
        name: "iphone",
        label: "iPhone",
        pattern: [
            "..#####..",
            "..#...#..",
            "..#...#..",
            "..#...#..",
            "..#...#..",
            "..#...#..",
            "..#.*.#..",
            "..#####..",
            ".........",
        ]
    )

    /// Space left.
    public static let spaceLeft = GlyphBitmap(
        name: "arrowL",
        label: "Space left",
        pattern: [
            ".........",
            ".........",
            "...#.....",
            "..#......",
            ".#######.",
            "..#......",
            "...#.....",
            ".........",
            ".........",
        ]
    )

    /// Space right.
    public static let spaceRight = GlyphBitmap(
        name: "arrowR",
        label: "Space right",
        pattern: [
            ".........",
            ".........",
            ".....#...",
            "......#..",
            ".#######.",
            "......#..",
            ".....#...",
            ".........",
            ".........",
        ]
    )

    /// Displays.
    public static let displays = GlyphBitmap(
        name: "displays",
        label: "Displays",
        pattern: [
            ".........",
            "#####....",
            "#...#....",
            "#...#####",
            "#####...#",
            "....#...#",
            "....#.*.#",
            "....#####",
            ".........",
        ]
    )

    /// Wired.
    public static let wired = GlyphBitmap(
        name: "wired",
        label: "Wired",
        pattern: [
            "...#.#...",
            "...#.#...",
            "..#####..",
            "..#...#..",
            "..#...#..",
            "...###...",
            "....#....",
            "....#....",
            "....*....",
        ]
    )

    /// VPN.
    public static let vpn = GlyphBitmap(
        name: "vpn",
        label: "VPN",
        pattern: [
            ".#######.",
            ".#.....#.",
            ".#.....#.",
            ".#..*..#.",
            ".#.....#.",
            "..#...#..",
            "...#.#...",
            "....#....",
            ".........",
        ]
    )

    /// Sound on.
    public static let soundOn = GlyphBitmap(
        name: "audio",
        label: "Sound on",
        pattern: [
            ".........",
            "...#.....",
            "..##..#..",
            "###.#..#.",
            "#...#..*.",
            "###.#..#.",
            "..##..#..",
            "...#.....",
            ".........",
        ]
    )

    /// Sound off.
    public static let soundOff = GlyphBitmap(
        name: "mute",
        label: "Sound off",
        pattern: [
            ".........",
            "...#.....",
            "..##.....",
            "###.#.#.#",
            "#...#..#.",
            "###.#.#.#",
            "..##.....",
            "...#.....",
            ".........",
        ]
    )

    /// Paste.
    public static let paste = GlyphBitmap(
        name: "paste",
        label: "Paste",
        pattern: [
            "..#####..",
            ".##...##.",
            ".#.....#.",
            ".#.###.#.",
            ".#.....#.",
            ".#.###.#.",
            ".#.....#.",
            ".#######.",
            ".........",
        ]
    )

    /// Type.
    public static let type = GlyphBitmap(
        name: "type",
        label: "Type",
        pattern: [
            "#########",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            "...#*#...",
        ]
    )

    /// Region.
    public static let region = GlyphBitmap(
        name: "region",
        label: "Region",
        pattern: [
            "#.#.#.#.#",
            ".........",
            "#.......#",
            ".........",
            "#...*...#",
            ".........",
            "#.......#",
            ".........",
            "#.#.#.#.#",
        ]
    )

    /// Read text.
    public static let readText = GlyphBitmap(
        name: "ocr",
        label: "Read text",
        pattern: [
            "##.....##",
            "#.......#",
            "..#####..",
            ".........",
            "..####...",
            ".........",
            "..#####..",
            "#.......#",
            "##.....##",
        ]
    )

    /// Pin.
    public static let pin = GlyphBitmap(
        name: "pin",
        label: "Pin",
        pattern: [
            "..#####..",
            "..#...#..",
            "..#...#..",
            ".#######.",
            "....#....",
            "....#....",
            "....#....",
            "....*....",
            ".........",
        ]
    )

    /// Close.
    public static let close = GlyphBitmap(
        name: "close",
        label: "Close",
        pattern: [
            ".........",
            ".#.....#.",
            "..#...#..",
            "...#.#...",
            "....#....",
            "...#.#...",
            "..#...#..",
            ".#.....#.",
            ".........",
        ]
    )

    /// Add.
    public static let add = GlyphBitmap(
        name: "plus",
        label: "Add",
        pattern: [
            "....#....",
            "....#....",
            "....#....",
            "....#....",
            "####*####",
            "....#....",
            "....#....",
            "....#....",
            "....#....",
        ]
    )

    /// Picture in Picture.
    public static let pictureInPicture = GlyphBitmap(
        name: "pip",
        label: "Picture in Picture",
        pattern: [
            ".........",
            "#########",
            "#.......#",
            "#.......#",
            "#...#####",
            "#...#...#",
            "#...#.*.#",
            "#########",
            ".........",
        ]
    )

    /// Wi-Fi.
    public static let wifi = GlyphBitmap(
        name: "wifi",
        label: "Wi-Fi",
        pattern: [
            ".........",
            "..#####..",
            ".#.....#.",
            "#.......#",
            "...###...",
            "..#...#..",
            ".........",
            "....*....",
            ".........",
        ]
    )

    /// Settings.
    public static let settings = GlyphBitmap(
        name: "settings",
        label: "Settings",
        pattern: [
            ".........",
            ".....#...",
            "####.#.##",
            ".....#...",
            ".........",
            "..#......",
            "##.#.####",
            "..#......",
            ".........",
        ]
    )

    /// Wake.
    public static let wake = GlyphBitmap(
        name: "power",
        label: "Wake",
        pattern: [
            "....*....",
            ".#..#..#.",
            "#...#...#",
            "#.......#",
            "#.......#",
            "#.......#",
            ".#.....#.",
            "..#####..",
            ".........",
        ]
    )

    /// Every glyph, in the board's order.
    public static let all: [GlyphBitmap] = [
        pointer, click, screen, deck, keyboard, capture,
        missionControl, showDesktop, play, pause, build, run,
        stop, test, find, console, lock, send,
        share, ask, mac, iPhone, spaceLeft, spaceRight,
        displays, wired, vpn, soundOn, soundOff, paste,
        type, region, readText, pin, close, add,
        pictureInPicture, wifi, settings, wake,
    ]

    /// Looks a glyph up by its board name (`"pointer"`, `"mission"`, …).
    public static func named(_ name: String) -> GlyphBitmap? {
        all.first { $0.name == name }
    }
}
