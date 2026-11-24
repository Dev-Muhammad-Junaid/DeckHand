//
//  DeckWidget.swift
//  DeckHandWidgets
//
//  The Deck widget (D6): small (2 × 2 keys) and medium (4 × 2), each key an
//  interactive `Button(intent:)`. Pro shows the deck's keys
//  (`WidgetDeckSnapshot.widgetKeys`); the free plan, or a deck with no
//  keys yet, shows the free Mac keys (Mission Control, Show Desktop,
//  Play/Pause, Lock Screen, …), which work without Pro.
//
//  The status strip names the last Mac in dot-matrix (`STUDIO · DECK`).
//  Pressing a key opens Pixel Hand and runs it there (`openAppWhenRun`):
//  the Mac connection lives in the app.
//

import AppIntents
import PixelHandCore
import SwiftUI
import WidgetKit

struct DeckEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDeckSnapshot
}

struct DeckTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeckEntry {
        DeckEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeckEntry) -> Void) {
        completion(DeckEntry(date: Date(), snapshot: PixelHandAppGroup.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeckEntry>) -> Void) {
        // The app reloads timelines whenever the deck, the plan or the Mac
        // changes, so there is nothing to schedule.
        completion(Timeline(entries: [DeckEntry(date: Date(), snapshot: PixelHandAppGroup.readSnapshot())], policy: .never))
    }
}

/// One button a widget draws.
enum WidgetButton: Identifiable, Hashable {
    case key(WidgetKey)
    case system(SystemActionOption)
    case media(MediaKeyOption)

    var id: String {
        switch self {
        case let .key(key): "key.\(key.id)"
        case let .system(option): "system.\(option.rawValue)"
        case let .media(option): "media.\(option.rawValue)"
        }
    }

    var label: String {
        switch self {
        case let .key(key): key.label
        case let .system(option): option.command.title
        case .media(.playPause): "Play"
        case .media(.next): "Next"
        case .media(.previous): "Back"
        }
    }

    var glyph: WidgetGlyph {
        switch self {
        case let .key(key): key.glyph
        case let .system(option): .pixel(name: option.command.glyphName)
        case .media(.playPause): .pixel(name: "play")
        case .media(.next): .pixel(name: "arrowR")
        case .media(.previous): .pixel(name: "arrowL")
        }
    }

    var tint: String? {
        if case let .key(key) = self { return key.tint }
        return nil
    }

    /// The free plan's keys, in the order a widget shows them.
    static let freeKeys: [WidgetButton] = [
        .system(.missionControl), .system(.showDesktop), .media(.playPause), .system(.lockScreen),
        .system(.appExpose), .media(.previous), .media(.next), .system(.launchpad),
    ]

    /// What a widget with room for `count` keys shows.
    static func buttons(for snapshot: WidgetDeckSnapshot, count: Int) -> [WidgetButton] {
        let keys = snapshot.isPro ? snapshot.widgetKeys.map(WidgetButton.key) : []
        return Array((keys.isEmpty ? freeKeys : keys).prefix(count))
    }
}

/// A button running `button`'s intent around `label`.
struct WidgetIntentButton<Label: View>: View {
    let button: WidgetButton
    @ViewBuilder let label: () -> Label

    var body: some View {
        switch button {
        case let .key(key):
            Button(intent: RunDeckKeyIntent(key: DeckKeyEntity(key)), label: label)
        case let .system(option):
            Button(intent: RunMacActionIntent(action: option), label: label)
        case let .media(option):
            Button(intent: PressMediaKeyIntent(key: option), label: label)
        }
    }
}

struct DeckWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PixelHandAppGroup.WidgetKind.deck, provider: DeckTimelineProvider()) { entry in
            DeckWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Deck")
        .description("Your Pixel Hand keys. Tap one to run it on your Mac.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct DeckWidgetView: View {
    let snapshot: WidgetDeckSnapshot
    @Environment(\.widgetFamily) private var family

    private var columns: Int { family == .systemMedium ? 4 : 2 }

    var body: some View {
        let buttons = WidgetButton.buttons(for: snapshot, count: columns * 2)
        VStack(alignment: .leading, spacing: 8) {
            statusStrip
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < buttons.count {
                                WidgetIntentButton(button: buttons[index]) {
                                    DeckWidgetKeyFace(button: buttons[index])
                                }
                                .buttonStyle(.plain)
                            } else {
                                RoundedRectangle(cornerRadius: 12).fill(WidgetPalette.screenRaised.opacity(0.5))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .containerBackground(for: .widget) { WidgetPalette.surface }
    }

    private var statusStrip: some View {
        let mac = snapshot.currentMac?.name ?? "PIXEL HAND"
        let suffix = snapshot.isPro && !snapshot.widgetKeys.isEmpty ? "DECK" : "MAC"
        return HStack(spacing: 5) {
            Circle()
                .fill(snapshot.currentMac == nil ? WidgetPalette.stripDim : WidgetPalette.mint)
                .frame(width: 4, height: 4)
            ViewThatFits(in: .horizontal) {
                WidgetDotText("\(mac) · \(suffix)", pitch: 1.6)
                WidgetDotText(mac, pitch: 1.6)
                WidgetDotText(String(mac.prefix(6)), pitch: 1.6)
            }
            .foregroundStyle(WidgetPalette.phosphor)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.currentMac.map { "Pixel Hand, \($0.name)" } ?? "Pixel Hand")
    }
}

struct DeckWidgetKeyFace: View {
    let button: WidgetButton

    var body: some View {
        VStack(spacing: 4) {
            WidgetGlyphView(glyph: button.glyph, side: 22)
                .foregroundStyle(WidgetPalette.glyphColor(tint: button.tint))
            Text(button.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetPalette.phosphor.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WidgetPalette.screenRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WidgetPalette.screenHigh, lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(button.label)
    }
}
