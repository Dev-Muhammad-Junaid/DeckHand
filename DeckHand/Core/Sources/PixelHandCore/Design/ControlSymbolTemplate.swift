//
//  ControlSymbolTemplate.swift
//  PixelHandCore – Design
//
//  Control Center controls only draw symbol images, so Pixel Hand's glyphs
//  ship there as custom SF Symbols (`06-Pixel-Identity.md` §8: "Widgets,
//  Control Center controls … use navy, glyphs"; VQ-076). This renders a
//  dot bitmap as an SF Symbols 3.0 template: one rounded-square path per
//  dot, the same 78 % dot and 30 % radius as everywhere else, with the
//  Ultralight, Regular and Black small variants identical (dots don't get
//  bolder), so Xcode can interpolate every weight.
//
//  `DeckHand/Scripts/make-control-symbols.sh` writes the templates into
//  the widget extension's asset catalog; the Core tests check their shape.
//

import Foundation

public enum ControlSymbolTemplate {
    /// One symbol the widget extension ships.
    public struct Symbol: Sendable, Hashable {
        /// The asset name, used as `Image(name)` in the control's label.
        public let name: String
        public let columns: Int
        public let rows: Int
        public let dots: [GlyphPoint]
    }

    /// The symbols the controls use: the deck key, Mission Control, the
    /// trackpad's hand, and the free Mac keys (system and media) a Deck Key
    /// can fall back to.
    public static let symbols: [Symbol] = {
        var list: [Symbol] = [hand]
        for glyph in [PixelGlyphs.deck, PixelGlyphs.missionControl, PixelGlyphs.showDesktop, PixelGlyphs.lock, PixelGlyphs.pointer, PixelGlyphs.play] {
            list.append(Symbol(name: symbolName(glyph: glyph.name), columns: GlyphBitmap.size, rows: GlyphBitmap.size, dots: glyph.litPoints))
        }
        return list
    }()

    /// The asset name for the glyph called `glyph` (`"mission"` →
    /// `"ph.mission"`).
    public static func symbolName(glyph: String) -> String { "ph.\(glyph)" }

    /// The asset name of the hand (the app icon's dot hand, outline only).
    public static let handName = "ph.hand"

    /// The app icon's hand, outline dots (the menu bar's "ready" look).
    public static let hand: Symbol = {
        var dots: [GlyphPoint] = []
        for (y, row) in MenuBarHand.handRows.enumerated() {
            for (x, cell) in row.enumerated() where cell == "X" {
                dots.append(GlyphPoint(x: x, y: y))
            }
        }
        return Symbol(name: handName, columns: MenuBarHand.width, rows: MenuBarHand.handRows.count, dots: dots)
    }()

    // MARK: - Template geometry (SF Symbols template v3.0)

    static let baselineS = 696.0
    /// Cap height of the small scale: Capline-S sits at 625.541.
    static let capHeight = 70.459
    /// The drawn height of every symbol: a little taller than the cap
    /// height, like SF Symbols' own glyphs.
    static let symbolHeight = 84.0
    /// Where each variant's origin sits on the artboard.
    static let variantOrigins: [(id: String, x: Double)] = [
        ("Ultralight-S", 560), ("Regular-S", 1390), ("Black-S", 2560),
    ]

    /// The template's SVG text.
    public static func svg(_ symbol: Symbol) -> String {
        let pitch = symbolHeight / Double(symbol.rows)
        let width = pitch * Double(symbol.columns)
        let top = -capHeight / 2 - symbolHeight / 2
        let path = dotsPath(symbol.dots, pitch: pitch, top: top)

        var guides = """
          <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="696" y2="696"/>
          <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="625.541" y2="625.541"/>
          <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1126" y2="1126"/>
          <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
          <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1556" y2="1556"/>
          <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>

        """
        var groups = ""
        for variant in variantOrigins {
            let left = format(variant.x)
            let right = format(variant.x + width)
            guides += """
              <line id="left-margin-\(variant.id)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(left)" x2="\(left)" y1="600.785" y2="720.121"/>
              <line id="right-margin-\(variant.id)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(right)" x2="\(right)" y1="600.785" y2="720.121"/>

            """
            groups += """
              <g id="\(variant.id)" transform="matrix(1 0 0 1 \(left) \(format(baselineS)))">
               <path d="\(path)"/>
              </g>

            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
         <!--glyph: "\(symbol.name)", point size: 100.0, font version: "", template writer version: "Pixel Hand"-->
         <g id="Notes">
          <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
          <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 3036 1933)" text-anchor="end">Template v.3.0</text>
         </g>
         <g id="Guides">
        \(guides) </g>
         <g id="Symbols">
        \(groups) </g>
        </svg>

        """
    }

    /// The asset catalog's `Contents.json` for a symbol set.
    public static func contentsJSON(_ symbol: Symbol) -> String {
        """
        {
          "info" : {
            "author" : "xcode",
            "version" : 1
          },
          "symbols" : [
            {
              "filename" : "\(symbol.name).svg",
              "idiom" : "universal"
            }
          ]
        }

        """
    }

    /// One closed rounded square per dot (cubic corners, which every SVG
    /// reader handles), in reading order.
    static func dotsPath(_ dots: [GlyphPoint], pitch: Double, top: Double) -> String {
        let side = pitch * DotGeometry.glyph.dotRatio
        let radius = side * DotGeometry.glyph.cornerRatio
        let inset = (pitch - side) / 2
        let k = radius * 0.4477 // 1 - 0.5523: the control point's distance from the corner
        let sorted = dots.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        return sorted.map { dot in
            let x0 = Double(dot.x) * pitch + inset
            let y0 = top + Double(dot.y) * pitch + inset
            let x1 = x0 + side
            let y1 = y0 + side
            let f = format
            return "M\(f(x0 + radius)) \(f(y0))"
                + "L\(f(x1 - radius)) \(f(y0))"
                + "C\(f(x1 - k)) \(f(y0)) \(f(x1)) \(f(y0 + k)) \(f(x1)) \(f(y0 + radius))"
                + "L\(f(x1)) \(f(y1 - radius))"
                + "C\(f(x1)) \(f(y1 - k)) \(f(x1 - k)) \(f(y1)) \(f(x1 - radius)) \(f(y1))"
                + "L\(f(x0 + radius)) \(f(y1))"
                + "C\(f(x0 + k)) \(f(y1)) \(f(x0)) \(f(y1 - k)) \(f(x0)) \(f(y1 - radius))"
                + "L\(f(x0)) \(f(y0 + radius))"
                + "C\(f(x0)) \(f(y0 + k)) \(f(x0 + k)) \(f(y0)) \(f(x0 + radius)) \(f(y0))Z"
        }.joined()
    }

    /// A coordinate with at most three decimals and no trailing zeros.
    static func format(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}
