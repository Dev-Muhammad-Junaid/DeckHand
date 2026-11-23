//
//  DeckSurface.swift
//  DeckHandiOS – Surfaces
//
//  The Deck surface (UX-020, D2/D3): the deck's pages from `DeckStore`,
//  one at a time, swiped or picked with the page dots. The header names the
//  page (the app's icon when it follows the front app), the dot-matrix
//  `PageCounter`, the pin and Edit. Keys sit on the whole-point grid
//  (`DeckGrid.pane`): 4 / 5–6 / 3 by class, 3 at AX1–AX2, rows at AX3+.
//  Each key shows its delivery dots from the Mac's receipt.
//
//  Edit mode: dotted keys with remove badges, tap a key for the inspector,
//  drag to reorder, the ghost "Add key" opens the action library, Undo /
//  Redo and the page menu in the header. Decks are Pro: in the free plan
//  the surface is a dimmed preview with an inline card.
//  Spec: `04-Interaction-Model.md` §2 Deck, §6; board "Deck", "Deck editor
//  (1.2)", "Deck at AX3", "Free tier".
//

import PixelHandCore
import SwiftUI

struct DeckSurface: View {
    let session: ControlSessionModel
    let sender: TrackpadSender

    @ObservedObject private var model = DeckSurfaceModel.shared
    @ObservedObject private var store = DeckStore.shared
    @Environment(\.entitlements) private var entitlements
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var inspected: InspectedKey?
    @State private var pendingInspect: InspectedKey?
    @State private var isLibraryPresented = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false
    @State private var isLockCardDismissed = false
    @State private var isPaywallPresented = false

    private var apps: [String: InstalledAppInfo] { InstalledAppInfo.byBundleID(session.installedApps) }
    private var pages: [DeckPage] { store.document.orderedPages }
    private var isUnlocked: Bool { entitlements.allows(.decks) }

    private var shownPage: DeckPage? {
        model.shownPageID.flatMap { store.document.page(id: $0) } ?? pages.first
    }

    var body: some View {
        GeometryReader { proxy in
            let band = typeSize.typeBand
            let grid = DeckGrid.pane(width: proxy.size.width, height: proxy.size.height, band: band)
            let asRows = band == .huge
            VStack(spacing: PixelHandTheme.Space.md) {
                if model.isEditing && isUnlocked {
                    editHeader(grid: grid)
                } else {
                    header(grid: grid)
                }
                pager(grid: grid, asRows: asRows)
                pageDots
            }
            .padding(.top, PixelHandTheme.Space.xs)
            .disabled(!isUnlocked)
            .opacity(isUnlocked ? (isMacLocked ? 0.55 : 1) : 0.45)
            .saturation(isUnlocked ? 1 : 0.4)
            .overlay(alignment: .top) {
                if !isUnlocked { lockCard.padding(.horizontal, grid.leadingMargin).padding(.top, 96) }
            }
        }
        .onChange(of: session.activeBundleID, initial: true) { _, bundleID in
            model.frontAppChanged(to: bundleID)
        }
        .onChange(of: isUnlocked) { _, unlocked in
            if !unlocked { model.isEditing = false }
        }
        .sheet(isPresented: $isLibraryPresented, onDismiss: presentPendingInspector) {
            ActionLibrarySheet(
                frontBundleID: session.activeBundleID,
                apps: session.installedApps,
                onPick: { key, needsDetails in
                    guard let pageID = shownPage?.id else { return }
                    if needsDetails {
                        pendingInspect = InspectedKey(pageID: pageID, key: key, isNew: true)
                    } else {
                        model.edit { _ = $0.addKey(key, toPage: pageID) }
                    }
                    isLibraryPresented = false
                }
            )
        }
        .sheet(item: $inspected) { item in
            KeyInspectorSheet(
                key: item.key,
                isNew: item.isNew,
                apps: session.installedApps,
                frontBundleID: session.activeBundleID,
                onSave: { key in
                    model.edit { document in
                        if item.isNew { _ = document.addKey(key, toPage: item.pageID) } else { document.updateKey(key, onPage: item.pageID) }
                    }
                },
                onDelete: item.isNew ? nil : {
                    model.edit { $0.removeKey(id: item.key.id, fromPage: item.pageID) }
                }
            )
        }
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView(reason: .feature(.decks))
        }
        .alert("Rename page", isPresented: $isRenaming) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                guard let id = shownPage?.id else { return }
                model.edit { $0.renamePage(id: id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(shownTitle)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Page", role: .destructive) { model.deleteShownPage() }
        } message: {
            Text("Its keys go too. You can undo this while editing.")
        }
    }

    private var isMacLocked: Bool {
        session.macLockState.bannerText(macName: "") != nil
    }

    private var shownTitle: String {
        shownPage?.displayTitle { apps[$0]?.displayName } ?? "Deck"
    }

    private var shownIndex: Int {
        guard let id = shownPage?.id else { return 0 }
        return pages.firstIndex { $0.id == id } ?? 0
    }

    // MARK: Header

    private func header(grid: DeckGrid) -> some View {
        HStack(spacing: PixelHandTheme.Space.md) {
            pageBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(shownTitle)
                    .font(.headline)
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if pages.count > 1 {
                PageCounter(current: shownIndex + 1, total: pages.count)
            }
            Button(action: model.togglePin) {
                PHGlyph(glyph: PixelGlyphs.pin, pitch: PixelPitch.chip)
                    .foregroundStyle(isPinned ? PixelHandTheme.accent : PixelHandTheme.ink2)
                    .frame(width: 36, height: 36)
                    .background(isPinned ? PixelHandTheme.accentTint : PixelHandTheme.fill2, in: Capsule())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "Unpin page" : "Pin page")
            .accessibilityHint("A pinned page stays when the app in front changes")
            Button("Edit") {
                GestureHaptic.light.trigger()
                withAnimation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion)) { model.isEditing = true }
            }
            .buttonStyle(.ph(.secondary, size: .small))
        }
        .padding(.leading, grid.leadingMargin)
        .padding(.trailing, grid.trailingMargin)
    }

    private var isPinned: Bool {
        guard let id = shownPage?.id else { return false }
        return store.document.pinnedPageID == id
    }

    private var subtitle: String {
        let page = "page \(shownIndex + 1) of \(pages.count)"
        if isPinned { return "Pinned · " + page }
        if model.followedBundleID != nil { return "Follows the front app · " + page }
        if !store.document.followFrontApp { return "Following off · " + page }
        return page.prefix(1).uppercased() + page.dropFirst()
    }

    @ViewBuilder
    private var pageBadge: some View {
        if let bundleID = shownPage?.appBundleID, let icon = DeckAppIcons.image(for: bundleID, in: apps) {
            icon.resizable().interpolation(.high).scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        } else {
            PHGlyph(glyph: pageGlyph(shownPage), pitch: PixelPitch.chip)
                .foregroundStyle(PixelHandTheme.accent)
                .frame(width: 32, height: 32)
                .background(PixelHandTheme.accentTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func pageGlyph(_ page: DeckPage?) -> GlyphBitmap {
        switch page?.kind {
        case .home?: PixelGlyphs.deck
        case .context?: PixelGlyphs.click
        case .shortcuts?: PixelGlyphs.run
        case .app?: PixelGlyphs.mac
        case .custom?, nil: PixelGlyphs.deck
        }
    }

    private func editHeader(grid: DeckGrid) -> some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            Button {
                model.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.ph(.secondary, size: .small))
            .disabled(!model.history.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            Text("Edit “\(shownTitle)”")
                .font(.headline)
                .foregroundStyle(PixelHandTheme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            pageMenu
            Button("Done") {
                GestureHaptic.light.trigger()
                withAnimation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion)) { model.isEditing = false }
            }
            .buttonStyle(.ph(.primary, size: .small))
        }
        .padding(.leading, grid.leadingMargin)
        .padding(.trailing, grid.trailingMargin)
    }

    private var pageMenu: some View {
        Menu {
            Button {
                model.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!model.history.canRedo)
            Section("Pages") {
                Button {
                    model.addPage(title: "Page \(pages.count + 1)", kind: .custom)
                } label: {
                    Label("New Page", systemImage: "plus.rectangle.on.rectangle")
                }
                if let front = session.activeBundleID, store.document.appPage(for: front) == nil {
                    Button {
                        model.addPage(title: apps[front]?.displayName ?? "", kind: .app(bundleID: front))
                    } label: {
                        Label("Page for \(apps[front]?.displayName ?? "This App")", systemImage: "app.badge")
                    }
                }
                if !store.document.pages.contains(where: { $0.kind == .context }) {
                    Button {
                        model.addPage(title: "Context", kind: .context)
                    } label: {
                        Label("Context Page", systemImage: "rectangle.on.rectangle")
                    }
                }
                if !store.document.pages.contains(where: { $0.kind == .shortcuts }) {
                    Button {
                        model.addPage(title: "Shortcuts", kind: .shortcuts)
                    } label: {
                        Label("Shortcuts Page", systemImage: "square.stack.3d.up")
                    }
                }
            }
            Section {
                Button {
                    renameText = shownPage?.title ?? ""
                    isRenaming = true
                } label: {
                    Label("Rename Page", systemImage: "pencil")
                }
                Toggle(isOn: Binding(get: { store.document.followFrontApp }, set: { model.setFollowsFrontApp($0) })) {
                    Label("Follow Front App", systemImage: "arrow.triangle.2.circlepath")
                }
                if shownPage?.isDeletable == true {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Page", systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(PixelHandTheme.ink)
                .frame(width: 36, height: 36)
                .background(PixelHandTheme.fill2, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Page options")
    }

    // MARK: Pages

    private func pager(grid: DeckGrid, asRows: Bool) -> some View {
        TabView(selection: Binding(
            get: { shownPage?.id ?? "" },
            set: { model.select(pageID: $0) }
        )) {
            ForEach(pages) { page in
                pageContent(page, grid: grid, asRows: asRows)
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion), value: shownPage?.id)
    }

    @ViewBuilder
    private func pageContent(_ page: DeckPage, grid: DeckGrid, asRows: Bool) -> some View {
        let keys = store.document.shownKeys(on: page, frontBundleID: session.activeBundleID)
        let editing = model.isEditing && isUnlocked
        if keys.isEmpty && !editing {
            emptyPage(page)
                .padding(.leading, grid.leadingMargin)
                .padding(.trailing, grid.trailingMargin)
                .padding(.bottom, PixelHandTheme.Space.sm)
        } else {
            ScrollView(showsIndicators: false) {
                Group {
                    if asRows {
                        LazyVStack(spacing: PixelHandTheme.Space.sm) {
                            ForEach(keys) { shown in keyView(shown, page: page, grid: grid, asRow: true) }
                            if editing { addRow }
                        }
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(grid.keySize), spacing: grid.gutter), count: grid.columns),
                            alignment: .leading,
                            spacing: grid.gutter
                        ) {
                            ForEach(keys) { shown in keyView(shown, page: page, grid: grid, asRow: false) }
                            if editing { addKey(size: grid.keySize) }
                        }
                    }
                }
                .padding(.leading, grid.leadingMargin)
                .padding(.trailing, grid.trailingMargin)
                .padding(.top, editing ? 14 : 2)
                .padding(.bottom, PixelHandTheme.Space.lg)
            }
        }
    }

    private func keyView(_ shown: DeckShownKey, page: DeckPage, grid: DeckGrid, asRow: Bool) -> some View {
        let editing = model.isEditing && isUnlocked
        // On the Context page the front app's keys belong to that app's page.
        let canEdit = shown.source != .frontApp
        return DeckKeyButton(
            key: shown.key,
            sender: sender,
            apps: apps,
            size: grid.keySize,
            asRow: asRow,
            isEditing: editing && canEdit,
            onEdit: { inspect(shown, page: page) },
            onRemove: { model.edit { $0.removeKey(id: shown.id, fromPage: page.id) } }
        )
        .opacity(editing && !canEdit ? 0.45 : 1)
        .contextMenu {
            if canEdit {
                keyMenu(shown, page: page)
            }
        }
        .modifier(ReorderModifier(isOn: editing && shown.source == .stored, keyID: shown.id) { dragged in
            model.edit { $0.moveKey(id: dragged, onto: shown.id, onPage: page.id) }
        })
        .accessibilityActions {
            if editing && shown.source == .stored {
                Button("Move earlier") { model.edit { $0.nudgeKey(id: shown.id, by: -1, onPage: page.id) } }
                Button("Move later") { model.edit { $0.nudgeKey(id: shown.id, by: 1, onPage: page.id) } }
            }
        }
    }

    @ViewBuilder
    private func keyMenu(_ shown: DeckShownKey, page: DeckPage) -> some View {
        Button {
            model.isEditing = true
            inspect(shown, page: page)
        } label: {
            Label("Edit Key", systemImage: "slider.horizontal.3")
        }
        Button {
            var key = shown.key
            key.confirm.toggle()
            model.edit { $0.updateKey(key, onPage: page.id) }
        } label: {
            Label(shown.key.confirm ? "Run Without Asking" : "Ask Before Running", systemImage: shown.key.confirm ? "checkmark.circle" : "questionmark.circle")
        }
        Button {
            var key = shown.key
            key.pinnedToFirstRow.toggle()
            model.edit { $0.updateKey(key, onPage: page.id) }
        } label: {
            Label(shown.key.pinnedToFirstRow ? "Unpin From First Row" : "Pin to First Row", systemImage: "pin")
        }
        Button {
            model.edit { _ = $0.duplicateKey(id: shown.id, onPage: page.id, frontBundleID: session.activeBundleID) }
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button(role: .destructive) {
            model.edit { $0.removeKey(id: shown.id, fromPage: page.id) }
        } label: {
            Label(shown.source == .curated ? "Hide" : "Remove", systemImage: "minus.circle")
        }
    }

    private func inspect(_ shown: DeckShownKey, page: DeckPage) {
        inspected = InspectedKey(pageID: page.id, key: shown.key, isNew: false)
    }

    private func presentPendingInspector() {
        guard let pending = pendingInspect else { return }
        pendingInspect = nil
        inspected = pending
    }

    private func addKey(size: CGFloat) -> some View {
        DeckKey(title: "Add key", glyph: PixelGlyphs.add, size: size, kind: .ghost) {
            isLibraryPresented = true
        }
        .accessibilityLabel("Add key")
        .accessibilityHint("Opens the action library")
    }

    private var addRow: some View {
        DeckKeyRow(title: "Add key", glyph: PixelGlyphs.add) {
            isLibraryPresented = true
        }
        .overlay {
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
                .strokeBorder(PixelHandTheme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .allowsHitTesting(false)
        }
    }

    private func emptyPage(_ page: DeckPage) -> some View {
        let appName = page.appBundleID.flatMap { apps[$0]?.displayName }
        let message: String = switch page.kind {
        case .shortcuts: "Add a key that runs one of the Mac’s Shortcuts."
        case .context: "Keys for the app in front show here."
        default: appName.map { "Add keys for \($0) from the action library." } ?? "Add keys from the action library."
        }
        return PixelSurface(cornerRadius: PixelHandTheme.Radius.pane) {
            PHEmptyState(
                glyph: PixelGlyphs.deck,
                title: "No keys yet",
                message: message,
                primaryTitle: "Add keys",
                primaryAction: {
                    model.isEditing = true
                    isLibraryPresented = true
                }
            )
        }
    }

    // MARK: Page dots

    @ViewBuilder
    private var pageDots: some View {
        if pages.count > 1 {
            HStack(spacing: 6) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        model.select(pageID: page.id)
                    } label: {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(index == shownIndex ? PixelHandTheme.accent : PixelHandTheme.ink3)
                            .frame(width: 6, height: 6)
                            .frame(width: pages.count > 8 ? 12 : 20, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(page.displayTitle { apps[$0]?.displayName })
                    .accessibilityAddTraits(index == shownIndex ? [.isSelected, .isButton] : .isButton)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pages")
            .padding(.bottom, PixelHandTheme.Space.xs)
        }
    }

    // MARK: Free plan

    @ViewBuilder
    private var lockCard: some View {
        if isLockCardDismissed {
            Button {
                isPaywallPresented = true
            } label: {
                Text("Decks · Pro")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, PixelHandTheme.Space.lg)
                    .frame(height: 36)
            }
            .buttonStyle(.ph(.tint, size: .small))
        } else {
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
                DotMatrixText("PRO", pitch: 2, label: "Pro")
                    .foregroundStyle(PixelHandTheme.accent)
                Text("Decks follow the app in front")
                    .font(.phDisplay(.title3))
                    .foregroundStyle(PixelHandTheme.ink)
                Text("Keys for every app, built from their real menus. Try every Pro feature free for 2 weeks.")
                    .font(.subheadline)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PixelHandTheme.Space.sm) {
                    Button("Try 2 weeks free") { isPaywallPresented = true }
                        .buttonStyle(.ph(.primary, size: .regular))
                    Button("Not now") { isLockCardDismissed = true }
                        .buttonStyle(.ph(.secondary, size: .regular))
                }
            }
            .padding(22)
            .frame(maxWidth: 420, alignment: .leading)
            .background(PixelHandTheme.elevated, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: PixelHandTheme.Brand.screen.opacity(0.3), radius: 25, y: 20)
        }
    }
}

/// A key the inspector is open for.
struct InspectedKey: Identifiable {
    let pageID: String
    let key: PixelHandCore.DeckKey
    let isNew: Bool
    var id: String { pageID + "/" + key.id }
}

/// Drag a stored key onto another to reorder (edit mode only).
private struct ReorderModifier: ViewModifier {
    let isOn: Bool
    let keyID: String
    let onDrop: (String) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if isOn {
            content
                .draggable(keyID)
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first, dragged != keyID else { return false }
                    GestureHaptic.selection.trigger()
                    onDrop(dragged)
                    return true
                } isTargeted: { isTargeted = $0 }
                .scaleEffect(isTargeted ? 1.06 : 1)
                .animation(.snappy(duration: 0.15), value: isTargeted)
        } else {
            content
        }
    }
}
