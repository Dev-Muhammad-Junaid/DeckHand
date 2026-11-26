//
//  KeyInspectorSheet.swift
//  DeckHandiOS – Deck
//
//  The key inspector (UX-020, D3; board "Deck editor (1.2)"): a live key
//  preview, the label, the glyph (one of the 9 × 9 set, the user's own
//  8 × 8 drawing, or the app's icon), the colour, what the key does (every
//  storable `Action`, sequences with their steps and pauses), Ask before
//  running and Pin to first row. Problems show inline in plain words
//  (`DeckValidation.keyIssues`) and Save stays off until they're fixed.
//  Save hands the key back; the surface records it for Undo.
//

import PixelHandCore
import SwiftUI

struct KeyInspectorSheet: View {
    let isNew: Bool
    let apps: [InstalledAppInfo]
    let frontBundleID: String?
    let onSave: (PixelHandCore.DeckKey) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var key: PixelHandCore.DeckKey
    @State private var source: GlyphSource
    @State private var setGlyphName: String
    @State private var pixels: PixelGlyphData
    @State private var isConfirmingDelete = false

    enum GlyphSource: String, CaseIterable, Identifiable {
        case set = "Glyph"
        case pixels = "Pixels"
        case app = "App icon"
        var id: String { rawValue }
    }

    init(
        key: PixelHandCore.DeckKey,
        isNew: Bool,
        apps: [InstalledAppInfo],
        frontBundleID: String?,
        onSave: @escaping (PixelHandCore.DeckKey) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.isNew = isNew
        self.apps = apps
        self.frontBundleID = frontBundleID
        self.onSave = onSave
        self.onDelete = onDelete
        _key = State(initialValue: key)
        let resolved = DeckGlyphs.resolve(key)
        var source = GlyphSource.set
        var name = DeckGlyphs.glyph(for: key.action).name
        var pixels = PixelGlyphData.blank(size: 8)
        switch key.appearance.glyph {
        case let .custom(bitmap)?:
            source = .pixels
            pixels = bitmap
        case .appIcon?:
            source = .app
        default:
            if case .appIcon = resolved { source = .app }
        }
        if case let .pixel(bitmap) = resolved, PixelGlyphs.named(bitmap.name) != nil {
            name = bitmap.name
            if source != .pixels { pixels = PixelGlyphData(bitmap: bitmap, size: 8) }
        }
        _source = State(initialValue: source)
        _setGlyphName = State(initialValue: name)
        _pixels = State(initialValue: pixels)
    }

    private var appsByID: [String: InstalledAppInfo] { InstalledAppInfo.byBundleID(apps) }

    /// The key as it will be saved, with the chosen glyph.
    private var edited: PixelHandCore.DeckKey {
        var copy = key
        copy.appearance.label = key.appearance.label.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source {
        case .set: copy.appearance.glyph = .pixel(id: setGlyphName)
        case .pixels: copy.appearance.glyph = .custom(bitmap: pixels)
        case .app: copy.appearance.glyph = (key.action.bundleID ?? frontBundleID).map { KeyGlyph.appIcon(bundleID: $0) }
        }
        return copy
    }

    private var messages: [String] {
        var seen = Set<String>()
        return DeckValidation.keyIssues(edited).compactMap(\.inspectorMessage).filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section("Label") {
                    TextField("Label", text: $key.appearance.label)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }
                glyphSection
                colourSection
                Section {
                    ActionFields(action: $key.action, apps: apps, frontBundleID: frontBundleID, allowsSequence: true)
                } header: {
                    Text("Action")
                } footer: {
                    Text(key.action.summary { appsByID[$0]?.displayName })
                }
                Section {
                    // A key that types always asks first (OT-8): the
                    // switch shows on and can't be turned off, with why.
                    Toggle("Ask before running", isOn: Binding(
                        get: { key.asksFirst },
                        set: { key.confirm = $0 }
                    ))
                    .disabled(key.asksFirstLockReason != nil)
                    .accessibilityIdentifier("ph.inspector.asksFirst")
                    Toggle("Pin to first row", isOn: $key.pinnedToFirstRow)
                } footer: {
                    if let reason = key.asksFirstLockReason {
                        Text(reason)
                    }
                }
                if !messages.isEmpty {
                    Section {
                        ForEach(messages, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.circle")
                                .foregroundStyle(PixelHandTheme.danger)
                                .font(.subheadline)
                        }
                    }
                }
                if let onDelete {
                    Section {
                        Button("Remove key", role: .destructive) { isConfirmingDelete = true }
                            .confirmationDialog("Remove “\(key.label)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                                Button("Remove", role: .destructive) {
                                    onDelete()
                                    dismiss()
                                }
                            }
                    }
                }
            }
            .navigationTitle(isNew ? "New key" : "Edit key")
            .accessibilityIdentifier("ph.deck.keyInspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        GestureHaptic.success.trigger()
                        onSave(edited)
                        dismiss()
                    }
                    .disabled(!messages.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Preview

    private var preview: some View {
        let face = DeckKeyFace(key: edited, apps: appsByID)
        return DeckKey(
            title: face.title.isEmpty ? " " : face.title,
            glyph: face.glyph,
            chord: face.chord,
            size: 96,
            kind: face.kind,
            asksFirst: key.asksFirst,
            icon: face.icon,
            tint: face.tint
        ) {}
        .allowsHitTesting(false)
        .accessibilityLabel("Preview of \(face.title)")
    }

    // MARK: Glyph

    private var glyphSection: some View {
        Section("Glyph") {
            Picker("Glyph", selection: $source) {
                ForEach(availableSources) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            switch source {
            case .set:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(PixelGlyphs.all) { glyph in
                        let isOn = glyph.name == setGlyphName
                        Button {
                            GestureHaptic.selection.trigger()
                            setGlyphName = glyph.name
                        } label: {
                            PHGlyph(glyph: glyph, pitch: PixelPitch.chip)
                                .foregroundStyle(isOn ? PixelHandTheme.accent : PixelHandTheme.ink)
                                .frame(width: 44, height: 44)
                                .background(isOn ? PixelHandTheme.accentTint : PixelHandTheme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    if isOn {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(PixelHandTheme.accent, lineWidth: PixelHandTheme.Stroke.selection)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(glyph.label)
                        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                        .phosphorFocusable(cornerRadius: 10)
                    }
                }
                .padding(.vertical, 4)
            case .pixels:
                PixelGlyphEditor(glyph: $pixels)
                    .padding(.vertical, 6)
            case .app:
                Text("Shows \(appName)’s icon from the Mac.")
                    .font(.subheadline)
                    .foregroundStyle(PixelHandTheme.ink2)
            }
        }
    }

    private var appName: String {
        (key.action.bundleID ?? frontBundleID).flatMap { appsByID[$0]?.displayName } ?? "the app"
    }

    private var availableSources: [GlyphSource] {
        (key.action.bundleID ?? frontBundleID) == nil ? [.set, .pixels] : GlyphSource.allCases
    }

    // MARK: Colour

    private var colourSection: some View {
        Section("Colour") {
            HStack(spacing: PixelHandTheme.Space.md) {
                ForEach(DeckKeyTint.allCases) { tint in
                    let isOn = DeckKeyTint(token: key.appearance.tint) == tint
                    Button {
                        GestureHaptic.selection.trigger()
                        key.appearance.tint = tint.token
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.swatch)
                            .frame(width: 28, height: 28)
                            .padding(3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(isOn ? tint.swatch : .clear, lineWidth: 2)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tint.title)
                    .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                    .phosphorFocusable(cornerRadius: 11)
                }
            }
        }
    }
}

// MARK: - Action fields

/// Edits one `Action`: its kind and that kind's fields. Used for the key
/// and, without sequences, for each step of a sequence.
struct ActionFields: View {
    @Binding var action: Action
    let apps: [InstalledAppInfo]
    let frontBundleID: String?
    let allowsSequence: Bool

    private var kinds: [ActionKind] {
        allowsSequence ? ActionKind.allCases : ActionKind.allCases.filter { $0 != .sequence }
    }

    var body: some View {
        Picker("Does", selection: Binding(
            get: { ActionKind(action) ?? .shortcut },
            set: { action = action.converted(to: $0, frontBundleID: frontBundleID) }
        )) {
            ForEach(kinds) { kind in
                Text(kind.title).tag(kind)
            }
        }
        switch action {
        case let .shortcut(keys):
            ChordField(keys: keys) { action = .shortcut(keys: $0) }
        case let .appShortcut(bundleID, keys):
            AppPicker(bundleID: bundleID, apps: apps) { action = .appShortcut(bundleID: $0, keys: keys) }
            ChordField(keys: keys) { action = .appShortcut(bundleID: bundleID, keys: $0) }
        case let .launchApp(bundleID):
            AppPicker(bundleID: bundleID, apps: apps) { action = .launchApp(bundleID: $0) }
        case let .menuCommand(bundleID, path):
            AppPicker(bundleID: bundleID, apps: apps) { action = .menuCommand(bundleID: $0, path: path) }
            MenuPathField(path: path) { action = .menuCommand(bundleID: bundleID, path: $0) }
        case let .system(macro):
            Picker("Mac action", selection: Binding(get: { macro }, set: { action = .system(action: $0) })) {
                ForEach(SystemMacro.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        case let .media(key):
            Picker("Media key", selection: Binding(get: { key }, set: { action = .media(key: $0) })) {
                ForEach(MediaKey.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        case let .macShortcut(name):
            TextField("Shortcut name", text: Binding(get: { name }, set: { action = .macShortcut(name: $0) }))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        case let .typeText(text):
            TypedTextFields(text: text) { action = .typeText(text: $0) }
        case let .sequence(steps):
            SequenceEditor(steps: Binding(get: { steps }, set: { action = .sequence(steps: $0) }), apps: apps, frontBundleID: frontBundleID)
        case .contextAction:
            Text("Dialog buttons can’t be saved on a key.")
                .foregroundStyle(PixelHandTheme.ink2)
        }
    }
}

/// An app from the Mac's list (or the stored bundle ID if the Mac hasn't
/// sent it).
private struct AppPicker: View {
    let bundleID: String
    let apps: [InstalledAppInfo]
    let onChange: (String) -> Void

    var body: some View {
        let sorted = apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        Picker("App", selection: Binding(get: { bundleID }, set: { onChange($0) })) {
            if !sorted.contains(where: { $0.bundleID == bundleID }) {
                Text(bundleID).tag(bundleID)
            }
            ForEach(sorted) { app in
                Text(app.displayName).tag(app.bundleID)
            }
        }
    }
}

/// Modifier toggles (⌘ ⇧ ⌥ ⌃) and the key, built in the Mac's order.
private struct ChordField: View {
    let keys: [String]
    let onChange: ([String]) -> Void

    @State private var text = ""

    private struct Modifier: Hashable {
        let name: String
        let glyph: String
        let label: String
    }

    private static let symbols = [
        Modifier(name: "cmd", glyph: "⌘", label: "Command"),
        Modifier(name: "shift", glyph: "⇧", label: "Shift"),
        Modifier(name: "option", glyph: "⌥", label: "Option"),
        Modifier(name: "ctrl", glyph: "⌃", label: "Control"),
    ]

    var body: some View {
        let split = ChordParsing.split(keys)
        HStack(spacing: PixelHandTheme.Space.sm) {
            ForEach(Self.symbols, id: \.name) { modifier in
                let isOn = split.modifiers.contains(modifier.name)
                Button {
                    var mods = split.modifiers
                    if isOn { mods.remove(modifier.name) } else { mods.insert(modifier.name) }
                    onChange(ChordParsing.chord(modifiers: mods, key: split.key) ?? ChordParsing.modifiers.filter { mods.contains($0) })
                } label: {
                    Text(modifier.glyph)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(isOn ? .white : PixelHandTheme.ink)
                        .frame(width: 44, height: 40)
                        .background(isOn ? PixelHandTheme.accent : PixelHandTheme.fill2, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(modifier.label)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
            TextField("Key", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 60)
                .onChange(of: text) { _, newValue in
                    let mods = ChordParsing.split(keys).modifiers
                    onChange(ChordParsing.chord(modifiers: mods, key: newValue) ?? ChordParsing.modifiers.filter { mods.contains($0) })
                }
        }
        .onAppear { text = split.key }
        Text("Keys: a letter or digit, or space, return, tab, escape, delete, up, down, left, right, f1–f12.")
            .font(.caption)
            .foregroundStyle(PixelHandTheme.ink3)
    }
}

/// The menu path typed as "File › Export › PDF…". The text stays as typed
/// while the action gets the parsed path.
private struct MenuPathField: View {
    let path: [String]
    let onChange: ([String]) -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("File › New Tab", text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onChange(of: text) { _, newValue in onChange(MenuPathText.parse(newValue)) }
            Text("Menu titles as they read on the Mac, separated by › or >.")
                .font(.caption)
                .foregroundStyle(PixelHandTheme.ink3)
        }
        .onAppear { text = MenuPathText.format(path) }
    }
}

// MARK: - Sequence

/// A sequence's steps: reorder, delete, edit each action, pauses with a
/// stepper. At most `ActionLimits.maxSequenceSteps`.
private struct SequenceEditor: View {
    @Binding var steps: [SequenceStep]
    let apps: [InstalledAppInfo]
    let frontBundleID: String?

    private var appsByID: [String: InstalledAppInfo] { InstalledAppInfo.byBundleID(apps) }

    var body: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            switch step {
            case let .run(action):
                NavigationLink {
                    Form {
                        ActionFields(
                            action: Binding(get: { action }, set: { replace(index, with: .run(action: $0)) }),
                            apps: apps,
                            frontBundleID: frontBundleID,
                            allowsSequence: false
                        )
                    }
                    .navigationTitle("Step \(index + 1)")
                } label: {
                    stepLabel(index: index, glyph: DeckGlyphs.glyph(for: action), title: action.summary { appsByID[$0]?.displayName })
                }
            case let .delay(milliseconds):
                Stepper(value: Binding(get: { milliseconds }, set: { replace(index, with: .delay(milliseconds: $0)) }), in: 0...ActionLimits.maxDelayMilliseconds, step: 100) {
                    stepLabel(index: index, glyph: PixelGlyphs.pause, title: "Wait \(String(format: "%.1f", Double(milliseconds) / 1000)) s")
                }
            }
        }
        .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
        .onDelete { steps.remove(atOffsets: $0) }
        if steps.count < ActionLimits.maxSequenceSteps {
            Menu {
                ForEach(ActionKind.allCases.filter { $0 != .sequence }) { kind in
                    Button(kind.title) { steps.append(.run(action: kind.template(frontBundleID: frontBundleID))) }
                }
                Button("Pause") { steps.append(.delay(milliseconds: 500)) }
            } label: {
                Label("Add step", systemImage: "plus.circle")
            }
        }
    }

    private func replace(_ index: Int, with step: SequenceStep) {
        guard steps.indices.contains(index) else { return }
        steps[index] = step
    }

    private func stepLabel(index: Int, glyph: GlyphBitmap, title: String) -> some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            DotMatrixText(String(format: "%02d", index + 1), pitch: 1.6, label: "Step \(index + 1)")
                .foregroundStyle(PixelHandTheme.ink3)
            PHGlyph(glyph: glyph, pitch: PixelPitch.chip)
                .foregroundStyle(PixelHandTheme.accent)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(PixelHandTheme.ink)
                .lineLimit(2)
        }
    }
}

/// Typed text (OT-8): what the key types, multi-line, and "Press Return
/// after" for its trailing line break (`TypedTextEditing`). The text is
/// kept as typed here while the action gets the cleaned form the Mac
/// types.
private struct TypedTextFields: View {
    let text: String
    let onChange: (String) -> Void

    @State private var draft = ""
    @State private var pressesReturn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Text to type", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("ph.inspector.typeText")
                .onChange(of: draft) { _, _ in commit() }
            Text("Types into the app in front on the Mac, then asks first each time.")
                .font(.caption)
                .foregroundStyle(PixelHandTheme.ink3)
        }
        Toggle("Press Return after", isOn: $pressesReturn)
            .accessibilityIdentifier("ph.inspector.typeReturn")
            .onChange(of: pressesReturn) { _, _ in commit() }
            .onAppear {
                let parts = TypedTextEditing.parts(text)
                draft = parts.body
                pressesReturn = parts.pressesReturn
            }
    }

    private func commit() {
        let next = TypedTextEditing.text(body: draft, pressesReturn: pressesReturn)
        if next != text { onChange(next) }
    }
}
