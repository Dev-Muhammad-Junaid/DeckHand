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
//  the surface is one empty state whose button carries the Pro lock.
//  The header goes to two rows when one would crush it (`DeckHeaderPlan`);
//  the page number is only in the dot-matrix counter.
//
//  Suggestions (UX-021, D7): under an app page's grid (and the Context
//  page's, for the front app), `DeckSuggestionsPanel` offers ghost keys
//  from the app's real menus, ranked on the device.
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
            let plan = DeckHeaderPlan(
                width: Double(proxy.size.width) - Double(grid.leadingMargin) - Double(grid.trailingMargin),
                band: band,
                pageCount: pages.count
            )
            if isUnlocked {
                VStack(spacing: PixelHandTheme.Space.md) {
                    Group {
                        if model.isEditing {
                            editHeader(grid: grid, plan: plan)
                        } else {
                            header(grid: grid, plan: plan)
                        }
                    }
                    // The whole header row, centred as before: the floating
                    // screen tile keeps clear of its counter, pin and Edit
                    // (build 19, `MirrorTilePlacement.surfaceLayout`).
                    .frame(maxWidth: .infinity)
                    .mirrorTileKeepOut(.deckHeader, owner: sender)
                    pager(grid: grid, asRows: asRows)
                        // VQ-083: while editing, the key slots are kept
                        // clear too; on iPhone that leaves no room, so the
                        // tile steps aside until Done.
                        .mirrorTileKeepOut(.deckEditGrid, owner: sender, isActive: model.isEditing)
                    pageDots
                }
                .padding(.top, PixelHandTheme.Space.xs)
                .opacity(isMacLocked ? 0.55 : 1)
            } else {
                // Free plan: one state, never the upsell over the empty
                // page (VQ-025, OR-03); the lock sits on the button.
                lockedState
                    .padding(.leading, grid.leadingMargin)
                    .padding(.trailing, grid.trailingMargin)
                    .padding(.vertical, PixelHandTheme.Space.xs)
            }
        }
        .onChange(of: session.activeBundleID, initial: true) { _, bundleID in
            model.frontAppChanged(to: bundleID)
        }
        .onAppear {
            if isUnlocked { model.ensureStandardPages() }
            DeckSuggestionsModel.shared.reorderer = isUnlocked ? OnDeviceDeckRanker.makeIfAvailable() : nil
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
        .alert("Rename page", isPresented: $isRenaming) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                guard let id = shownPage?.id else { return }
                model.edit { $0.renamePage(id: id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(shownTitle)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete page", role: .destructive) { model.deleteShownPage() }
        } message: {
            Text("Its keys go too. You can undo this while editing.")
        }
    }

    /// The dialog open on the Mac, for the Context page's keys.
    private var dialog: DialogContext? {
        if case let .dialog(dialog) = session.uiContext { return dialog }
        return nil
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

    /// Name, counter, pin and Edit: one row when `DeckHeaderPlan` says it
    /// fits, otherwise the name on its own row and the controls under it
    /// (iPad deck columns, Large and Huge type; VQ-024, VQ-065).
    @ViewBuilder
    private func header(grid: DeckGrid, plan: DeckHeaderPlan) -> some View {
        Group {
            if plan.isOneRow {
                HStack(spacing: PixelHandTheme.Space.md) {
                    pageBadge
                    pageTitle
                    if plan.showsCounter { counter }
                    pinButton
                    editButton
                }
            } else {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                    HStack(spacing: PixelHandTheme.Space.md) {
                        pageBadge
                        pageTitle
                    }
                    HStack(spacing: PixelHandTheme.Space.sm) {
                        if plan.showsCounter { counter }
                        Spacer(minLength: 0)
                        pinButton
                        editButton
                    }
                }
            }
        }
        .padding(.leading, grid.leadingMargin)
        .padding(.trailing, grid.trailingMargin)
    }

    private var pageTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shownTitle)
                .font(.headline)
                .foregroundStyle(PixelHandTheme.ink)
                .lineLimit(typeSize.typeBand == .huge ? 2 : 1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .lineLimit(typeSize.typeBand == .standard ? 1 : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The page number, in dot-matrix only (the subtitle no longer repeats
    /// it; VQ-082).
    private var counter: some View {
        PageCounter(current: shownIndex + 1, total: pages.count)
    }

    private var pinButton: some View {
        Button {
            model.togglePin()
        } label: {
            PHGlyph(glyph: PixelGlyphs.pin, pitch: PixelPitch.chip)
                .foregroundStyle(isPinned ? PixelHandTheme.accent : PixelHandTheme.ink2)
                .frame(width: 36, height: 36)
                .background(isPinned ? PixelHandTheme.accentTint : PixelHandTheme.fill2, in: Capsule())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .phosphorFocusable(cornerRadius: 18)
        .accessibilityLabel(isPinned ? "Unpin page" : "Pin page")
        .accessibilityIdentifier("ph.deck.pin")
        .accessibilityHint("A pinned page stays when the app in front changes")
    }

    private var editButton: some View {
        Button("Edit") {
            GestureHaptic.light.trigger()
            withAnimation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion)) { model.isEditing = true }
        }
        .buttonStyle(.ph(.secondary, size: .small))
        .accessibilityIdentifier("ph.deck.edit")
    }

    private var isPinned: Bool {
        guard let id = shownPage?.id else { return false }
        return store.document.pinnedPageID == id
    }

    private var subtitle: String? {
        DeckHeaderPlan.subtitle(
            isPinned: isPinned,
            followsApp: model.followedBundleID != nil,
            followingOn: store.document.followFrontApp
        )
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

    /// Undo, the page name, the page menu and Done; the name gets its own
    /// row when one row would wrap a button (VQ-065).
    @ViewBuilder
    private func editHeader(grid: DeckGrid, plan: DeckHeaderPlan) -> some View {
        Group {
            if plan.isOneRow {
                HStack(spacing: PixelHandTheme.Space.sm) {
                    undoButton(glyphOnly: plan.undoIsGlyphOnly)
                    editTitle
                        .frame(maxWidth: .infinity)
                    pageMenu
                    doneButton
                }
            } else {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                    editTitle
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: PixelHandTheme.Space.sm) {
                        undoButton(glyphOnly: plan.undoIsGlyphOnly)
                        Spacer(minLength: 0)
                        pageMenu
                        doneButton
                    }
                }
            }
        }
        .padding(.leading, grid.leadingMargin)
        .padding(.trailing, grid.trailingMargin)
    }

    private var editTitle: some View {
        Text("Edit “\(shownTitle)”")
            .font(.headline)
            .foregroundStyle(PixelHandTheme.ink)
            .lineLimit(typeSize.typeBand == .huge ? 2 : 1)
    }

    @ViewBuilder
    private func undoButton(glyphOnly: Bool) -> some View {
        Button {
            model.undo()
        } label: {
            if glyphOnly {
                Image(systemName: "arrow.uturn.backward")
                    .accessibilityLabel("Undo")
            } else {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
        }
        .buttonStyle(.ph(.secondary, size: .small))
        .disabled(!model.history.canUndo)
        .keyboardShortcut("z", modifiers: .command)
        .accessibilityShowsLargeContentViewer {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
    }

    private var doneButton: some View {
        Button("Done") {
            GestureHaptic.light.trigger()
            withAnimation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion)) { model.isEditing = false }
        }
        .buttonStyle(.ph(.primary, size: .small))
        .accessibilityIdentifier("ph.deck.done")
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
                    Label("New page", systemImage: "plus.rectangle.on.rectangle")
                }
                if let front = session.activeBundleID, store.document.appPage(for: front) == nil {
                    Button {
                        model.addPage(title: apps[front]?.displayName ?? "", kind: .app(bundleID: front))
                    } label: {
                        Label("Page for \(apps[front]?.displayName ?? "this app")", systemImage: "app.badge")
                    }
                }
                if !store.document.pages.contains(where: { $0.kind == .context }) {
                    Button {
                        model.addPage(title: "Context", kind: .context)
                    } label: {
                        Label("Context page", systemImage: "rectangle.on.rectangle")
                    }
                }
                if !store.document.pages.contains(where: { $0.kind == .shortcuts }) {
                    Button {
                        model.addPage(title: "Shortcuts", kind: .shortcuts)
                    } label: {
                        Label("Shortcuts page", systemImage: "square.stack.3d.up")
                    }
                }
            }
            Section {
                Button {
                    renameText = shownPage?.title ?? ""
                    isRenaming = true
                } label: {
                    Label("Rename page", systemImage: "pencil")
                }
                Toggle(isOn: Binding(get: { store.document.followFrontApp }, set: { model.setFollowsFrontApp($0) })) {
                    Label("Follow front app", systemImage: "arrow.triangle.2.circlepath")
                }
                if shownPage?.isDeletable == true {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete page", systemImage: "trash")
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
        .phosphorFocusable(cornerRadius: 18)
        .accessibilityLabel("Page options")
        .accessibilityIdentifier("ph.deck.pageMenu")
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
        let keys = store.document.shownKeys(on: page, frontBundleID: session.activeBundleID, dialog: dialog)
        let editing = model.isEditing && isUnlocked
        let target = suggestionTarget(page)
        if keys.isEmpty && !editing && target == nil {
            emptyPage(page)
                .padding(.leading, grid.leadingMargin)
                .padding(.trailing, grid.trailingMargin)
                .padding(.bottom, PixelHandTheme.Space.sm)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
                    if keys.isEmpty && !editing {
                        emptyPage(page)
                    } else if asRows {
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
                            if editing {
                                addKey(size: grid.keySize)
                                // Fill the row with dashed ghost slots, so an
                                // empty page reads as editable (VQ-048).
                                ForEach(0..<ghostSlots(keyCount: keys.count, columns: grid.columns), id: \.self) { _ in
                                    ghostSlot(size: grid.keySize)
                                }
                            }
                        }
                    }
                    if let target {
                        DeckSuggestionsPanel(
                            bundleID: target,
                            appName: apps[target]?.displayName ?? page.displayTitle { apps[$0]?.displayName },
                            isFrontApp: target == session.activeBundleID,
                            sender: sender,
                            apps: apps,
                            grid: grid,
                            asRows: asRows
                        )
                    }
                }
                .padding(.leading, grid.leadingMargin)
                .padding(.trailing, grid.trailingMargin)
                .padding(.top, editing ? 14 : 2)
                .padding(.bottom, PixelHandTheme.Space.lg)
            }
        }
    }

    /// The app a page suggests keys for (UX-021): an app page's own app,
    /// or the front app on the Context page. `nil` in the free plan.
    private func suggestionTarget(_ page: DeckPage) -> String? {
        guard isUnlocked else { return nil }
        switch page.kind {
        case let .app(bundleID): return bundleID
        case .context: return session.activeBundleID
        case .home, .shortcuts, .custom: return nil
        }
    }

    private func keyView(_ shown: DeckShownKey, page: DeckPage, grid: DeckGrid, asRow: Bool) -> some View {
        let editing = model.isEditing && isUnlocked
        // The front app's keys belong to that app's page; dialog buttons
        // only exist while the dialog is open.
        let canEdit = shown.isEditable
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
            Label("Edit key", systemImage: "slider.horizontal.3")
        }
        Button {
            var key = shown.key
            key.confirm.toggle()
            model.edit { $0.updateKey(key, onPage: page.id) }
        } label: {
            Label(shown.key.confirm ? "Run without asking" : "Ask before running", systemImage: shown.key.confirm ? "checkmark.circle" : "questionmark.circle")
        }
        Button {
            var key = shown.key
            key.pinnedToFirstRow.toggle()
            model.edit { $0.updateKey(key, onPage: page.id) }
        } label: {
            Label(shown.key.pinnedToFirstRow ? "Unpin from first row" : "Pin to first row", systemImage: "pin")
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

    /// Empty dashed slots after "Add key" up to the end of its row (a full
    /// first row on an empty page).
    private func ghostSlots(keyCount: Int, columns: Int) -> Int {
        let columns = max(1, columns)
        let used = (keyCount + 1) % columns
        return used == 0 ? 0 : columns - used
    }

    private func ghostSlot(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
            .strokeBorder(PixelHandTheme.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .onTapGesture { isLibraryPresented = true }
            .accessibilityHidden(true)
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
                    .accessibilityIdentifier("ph.deck.pageDot")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pages")
            .padding(.bottom, PixelHandTheme.Space.xs)
        }
    }

    // MARK: Free plan

    /// The free plan's deck: one empty state whose button carries the Pro
    /// lock (OR-03: no upsell card; the paywall opens from the button).
    private var lockedState: some View {
        PixelSurface(cornerRadius: PixelHandTheme.Radius.pane) {
            PHEmptyState(
                glyph: PixelGlyphs.deck,
                title: "Decks",
                message: "Keys for every app, built from their real menus.",
                primaryTitle: "Show decks",
                primaryAction: {},
                primaryRequires: .decks
            )
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
