//
//  DeckAccessoryWidget.swift
//  DeckHandWidgets
//
//  The Lock Screen widget (D6). Circular: the first key (Mission Control
//  on the free plan) as one button on the system's accessory disc.
//  Rectangular: the Mac's name in dot-matrix over three key buttons.
//  Monochrome, so glyphs draw in the foreground style and the accent dot
//  isn't coloured.
//
//  The name shortens at word boundaries until it fits ("Muhammad's
//  MacBook Pro" → "Muhammad's"), then falls back to the Mac glyph alone;
//  it never runs past the widget's edges (VQ-074).
//

import AppIntents
import PixelHandCore
import SwiftUI
import WidgetKit

struct DeckAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PixelHandAppGroup.WidgetKind.accessory, provider: DeckTimelineProvider()) { entry in
            DeckAccessoryView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Mac Keys")
        .description("Run a key on your Mac from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct DeckAccessoryView: View {
    let snapshot: WidgetDeckSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            default: circular
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        let button = WidgetButton.buttons(for: snapshot, count: 1).first ?? .system(.missionControl)
        return ZStack {
            // The container background doesn't draw on the Lock Screen's
            // circular slot, so the disc is part of the view (VQ-075): it
            // sits with the system's circular widgets instead of reading as
            // a stray icon.
            AccessoryWidgetBackground()
            WidgetIntentButton(button: button) {
                WidgetGlyphView(glyph: button.glyph, side: 27, accent: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Circle())
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(button.label)
        }
    }

    private var rectangular: some View {
        let buttons = WidgetButton.buttons(for: snapshot, count: 3)
        let mac = snapshot.currentMac
        return VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                ForEach(StatusStripText.candidates(name: mac?.name ?? "Pixel Hand", details: []), id: \.self) { line in
                    WidgetDotText(line, pitch: 1.4)
                }
                // Not even the first word fits: the Mac glyph alone.
                WidgetGlyphView(glyph: .pixel(name: PixelGlyphs.mac.name), side: 9 * 1.4, accent: nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mac?.name ?? "Pixel Hand")
            HStack(spacing: 6) {
                ForEach(buttons) { button in
                    WidgetIntentButton(button: button) {
                        WidgetGlyphView(glyph: button.glyph, side: 18, accent: nil)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.16)))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(button.label)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
