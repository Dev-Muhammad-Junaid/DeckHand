//
//  PixelHandShell.swift
//  DeckHandiOS – Shell
//
//  The Pixel Hand control surface (Option A "Dock & Canvas"): header,
//  status pills, the canvas, the context strip, the app dock and the tab
//  bar or layout presets. The shell reads its own size (never the device
//  idiom) into a `CanvasPlan` (Core) and lays out one of seven forms
//  (UX-007 arrangements, UX-040 iPhone Duo):
//
//    single      compact: one surface; strip, dock and tab bar below
//    rail        iPhone landscape: tab rail · pad · deck column with the
//                header and strip on top (dock folded into the strip)
//    stacked     ½ Split View: the surface over a resizable deck panel
//    sideBySide  iPad portrait: presets in the header; screen over
//                pad | deck; strip, then the dock with Ask beside it
//    columns     iPad landscape: Macs sidebar · centre (presets, Ask field,
//                screen over pad, floating dock) · deck column (strip on top)
//    book        iPhone Duo open (vertical crease): screen over pad and the
//                dock | crease | header, strip, deck, tab bar
//    laptop      iPhone Duo half-folded (horizontal crease): header and
//                screen | crease | strip, pad or deck, tab bar
//
//  The crease comes from the system's division region on iOS 27.1, or is
//  inferred from the window size on a phone (`DuoCrease`,
//  `DuoPoseMachine`). Nothing is laid out in its 40 pt band.
//
//  The presets (Split, Screen, Pointer) are remembered per Mac and form;
//  the screen/pad split, deck panel height, sidebar state and the selected
//  surface are scene storage, so they survive rotation, Split View, Stage
//  Manager resizes and scene restoration.
//
//  The right column (rail, sideBySide, columns: the deck and the front
//  app's shortcuts) switches Deck | Ask, and on iPad collapses to a slim
//  edge handle, remembered per arrangement (`RightColumnPlan`,
//  `RightColumnMemory`; OR-06). Ask (⌘K, the Ask field or circle) runs in
//  place in the column wherever there is one, and in its sheet elsewhere.
//  Panels fade; nothing slides in.
//
//  The keyboard (owner testing, build 24, OT-2): the shell plans its form
//  from the window and lays out under the on-screen keyboard (it ignores
//  the keyboard's safe area), so the keyboard never changes the
//  arrangement. The Type panel has one owner (`TypePanelModel`, in the
//  environment for the pad's keyboard button) and one place on screen
//  (`TypePanelHost`, laid over every form above the keyboard or the dock),
//  so its text field keeps the keyboard through rotation and resizes.
//
//  The surfaces keep their reserved areas: the pad's click strip and
//  caption sit at its own foot, and the floating screen tile is laid over
//  the pad alone, so its 120 pt band lines up with the pad's foot.
//  `ControlView` owns the session and the sheets; this view only reads.
//

import SwiftUI

struct PixelHandShell: View {
    let session: ControlSessionModel
    let peerName: String
    /// The approval state the root view shows, after timeout mapping.
    let authStatus: String
    let onSettings: () -> Void
    let onClassicLayout: () -> Void
    let onDisconnect: () -> Void

    @EnvironmentObject private var settings: DeckHandSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.entitlements) private var entitlements
    @SceneStorage("pixelhand.shell.surface") private var surfaceRawValue = ControlSurface.pointer.rawValue
    /// The screen's share of the Split preset (0 = follow the picture).
    @SceneStorage("pixelhand.layout.screenShare") private var screenShare: Double = 0
    /// The stacked deck panel's height (0 = one row of keys).
    @SceneStorage("pixelhand.layout.deckPanel") private var deckPanelHeight: Double = 0
    @SceneStorage("pixelhand.layout.sidebarCollapsed") private var sidebarCollapsed = false
    /// Presets per Mac and form (`LayoutPresetMemory`).
    @AppStorage("pixelhand.layout.presets") private var presetMemoryJSON = "{}"
    /// Collapsed right columns per arrangement (`RightColumnMemory`).
    @AppStorage("pixelhand.layout.rightColumn") private var rightColumnJSON = "[]"
    /// What the right column shows: the deck or Ask.
    @SceneStorage("pixelhand.layout.rightColumnMode") private var columnModeRawValue = RightColumnMode.deck.rawValue
    /// Bumped to focus Ask's field when Ask opens in the column.
    @State private var askFocusRequest = 0
    @State private var isAskPresented = false
    @State private var isMyMacsPresented = false
    /// The Type panel: open/closed, mode, tab (OT-2, OT-3). One per window.
    @State private var typePanel = TypePanelModel()
    @State private var shortcutsApp: InstalledAppInfo?
    /// A pane split while its handle is dragged (screen height or deck
    /// panel height), committed to scene storage on release.
    @State private var dragSize: CGFloat?
    /// The dock's stable order (`AppDockPlan`), updated as apps launch and quit.
    @State private var dockOrder: [String] = []
    @ObservedObject private var shortcuts = ShortcutStore.shared
    /// The hinge status (iOS 27.1+), and the pose machine fed each pass.
    @State private var hingeStatus: DuoHingeStatus?
    @State private var duoPose = DuoPoseMachine()

    /// Below this height the app dock folds into the strip's leading app
    /// chip (iPhone SE, Duo cover; `03-Layout-Strategy.md` Option A).
    private static let foldedDockHeight: CGFloat = 700

    private var selection: Binding<ControlSurface> {
        Binding(
            get: { ControlSurface(rawValue: surfaceRawValue) ?? .pointer },
            set: { surfaceRawValue = $0.rawValue }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let crease = DuoPoseMachine.band(for: DuoCrease.input(proxy: proxy, hingeStatus: hingeStatus))
            // The window's size: this reader ignores the keyboard's safe
            // area, so the keyboard can't change the form (OT-2).
            let size = ShellPlanningSize.size(measuredWidth: Double(proxy.size.width), measuredHeight: Double(proxy.size.height))
            let base = CanvasPlan(
                width: size.width,
                height: size.height,
                sidebarCollapsed: sidebarCollapsed,
                crease: crease
            )
            // A collapsed wide column gives the centre its room, so the plan
            // is made again with it (the arrangement key needs the form).
            let plan = base.form == .columns && rightColumn(base).isCollapsed
                ? CanvasPlan(
                    width: size.width,
                    height: size.height,
                    sidebarCollapsed: sidebarCollapsed,
                    rightColumnCollapsed: true,
                    crease: crease
                )
                : base

            ZStack {
                PixelHandTheme.canvas.ignoresSafeArea()

                switch plan.form {
                case .single, .stacked:
                    tabbedLayout(plan: plan, height: proxy.size.height)
                case .rail:
                    railLayout(plan: plan)
                case .sideBySide:
                    sideBySideLayout(plan: plan)
                case .columns:
                    columnsLayout(plan: plan)
                case .book, .laptop:
                    if let panes = plan.duoPanes {
                        duoLayout(plan: plan, panes: panes)
                    }
                }

                // One place for the Type panel in every form: its field
                // keeps its identity, so the keyboard stays up (OT-2).
                TypePanelHost(
                    session: session,
                    model: typePanel,
                    windowSize: proxy.size,
                    showsDock: showsDock(plan),
                    arrangement: plan.form.rawValue
                )
            }
            .animation(PixelHandMotion.reduced(PixelHandMotion.spring, reduceMotion: reduceMotion), value: plan.form)
            // The sidebar fades in and out; it never slides (OR-06 motion rule).
            .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: plan.showsSidebar)
            .onChange(of: crease, initial: true) { _, _ in
                let input = DuoCrease.input(proxy: proxy, hingeStatus: hingeStatus)
                // A pane drag in flight belongs to the old panes: drop it
                // when the device folds, unfolds or turns.
                if duoPose.update(input) != nil { dragSize = nil }
            }
            // Intents lane: "Open Trackpad", "Start Mirror". On preset
            // windows "Trackpad" also opens the Pointer arrangement (VQ-079).
            .intentSurfaceRequests(selection: selection, preset: plan.usesPresets ? presetBinding(plan) : nil)
        }
        // The shell lays out under the on-screen keyboard; the Type panel
        // rides on top of it (OT-2).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.typePanel, typePanel)
        .duoHingeStatus($hingeStatus)
        .sheet(isPresented: $isAskPresented) {
            AskSheet(session: session, macName: peerName)
        }
        .sheet(isPresented: $isMyMacsPresented) {
            MyMacsSheet( // Multi-Mac lane: UX-030 replaces the placeholder
                currentMacName: peerName,
                currentSubtitle: headerSubtitle,
                isLive: isLive,
                onDisconnect: {
                    isMyMacsPresented = false
                    onDisconnect()
                }
            )
        }
        .sheet(item: $shortcutsApp) { app in
            if let sender = session.sender {
                AppShortcutsSheet(app: app, sender: sender) { shortcutsApp = nil }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .perMacSurface($surfaceRawValue) // Multi-Mac lane: each Mac keeps its surface
        .onChange(of: session.runningBundleIDs, initial: true) { _, running in
            dockOrder = AppDockPlan.order(previous: dockOrder, running: running)
        }
    }

    private var headerSubtitle: String {
        ApprovalStatusCopy.headerSubtitle(status: authStatus, activeAppName: session.activeAppName)
    }

    private var isLive: Bool {
        ApprovalStatusCopy.showsLiveIndicator(status: authStatus)
    }

    // MARK: - Forms

    /// single and stacked: header, the canvas, then strip, dock and tab bar.
    @ViewBuilder
    private func tabbedLayout(plan: CanvasPlan, height: CGFloat) -> some View {
        let metrics = plan.metrics
        let centre = selection.wrappedValue.centre(hasDeckColumn: false)
        VStack(spacing: PixelHandTheme.Space.xs) {
            header()
            statusPills
                .padding(.horizontal, CGFloat(metrics.margin))
            if plan.form == .stacked && centre != .deck {
                stackedCanvas(centre: centre, plan: plan)
            } else {
                canvas(centre: centre, plan: plan)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: PixelHandTheme.Space.sm) {
            VStack(spacing: PixelHandTheme.Space.sm) {
                bottomChrome(metrics: metrics, foldsDock: height < Self.foldedDockHeight)
                // The tab bar stays put while typing: the keyboard covers
                // the shell's foot and the Type panel rides above it, so
                // nothing here moves (OT-2).
                SurfaceTabBar(
                    selection: selection,
                    tabs: ControlSurface.tabs(includeDeck: true),
                    onAsk: { openAsk(plan) }
                )
                .padding(.horizontal, CGFloat(metrics.margin))
            }
        }
    }

    /// iPhone landscape: the tab rail, the pad, and the deck column with the
    /// header and strip on top. Without room for the column, the rail keeps
    /// the deck tab and the strip sits under the canvas.
    @ViewBuilder
    private func railLayout(plan: CanvasPlan) -> some View {
        let metrics = plan.metrics
        let centre = selection.wrappedValue.centre(hasDeckColumn: plan.hasDeckColumn)
        HStack(spacing: CGFloat(metrics.gutter)) {
            SurfaceTabBar(
                selection: selection,
                tabs: ControlSurface.tabs(includeDeck: plan.tabSurfacesIncludeDeck),
                axis: .vertical,
                // VQ-105: no dock here, and the Screen tab's mirror takes
                // the whole pad, so the rail carries the keyboard button.
                keyboard: plan.railCarriesKeyboard
                    ? RailKeyboardButton.Config(isShown: typePanel.isShown) { typePanel.toggle() }
                    : nil,
                onAsk: { openAsk(plan) }
            )
            .padding(.leading, PixelHandTheme.Space.sm)
            .frame(maxHeight: .infinity)

            if plan.hasDeckColumn {
                canvas(centre: centre, plan: plan, margin: 0)
                // The column holds the header, so it never collapses; it
                // still switches Deck | Ask.
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                    header(showsMirrorToggle: false, horizontalPadding: 0)
                    statusPills(offersKeyboard: false)
                    RightColumnSwitch(mode: columnMode, canCollapse: false, onCollapse: {})
                    Group {
                        if columnMode.wrappedValue == .ask {
                            askColumn(framed: false)
                        } else {
                            VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                                stripOnly(metrics: metrics, foldedDock: true, margin: 0)
                                if let sender = session.sender {
                                    deck(sender: sender, columns: plan.deckColumnKeys, inset: 0)
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
                .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: columnMode.wrappedValue)
                .frame(width: CGFloat(plan.deckColumnWidth))
                .padding(.trailing, CGFloat(metrics.margin))
            } else {
                VStack(spacing: PixelHandTheme.Space.xs) {
                    header()
                    statusPills(offersKeyboard: false)
                        .padding(.horizontal, CGFloat(metrics.margin))
                    canvas(centre: centre, plan: plan)
                    stripOnly(metrics: metrics, foldedDock: true, margin: CGFloat(metrics.margin))
                }
            }
        }
    }

    /// iPad portrait and other medium windows ≥ 700 pt wide: presets in the
    /// header; the preset's panes; then strip, and the dock with Ask.
    @ViewBuilder
    private func sideBySideLayout(plan: CanvasPlan) -> some View {
        let metrics = plan.metrics
        let margin = CGFloat(metrics.margin)
        let preset = presetBinding(plan)
        VStack(spacing: PixelHandTheme.Space.xs) {
            header(presets: preset, horizontalPadding: margin)
            statusPills
                .padding(.horizontal, margin)
            Group {
                switch preset.wrappedValue {
                case .split:
                    GeometryReader { proxy in
                        screenOverPane(size: proxy.size) {
                            HStack(spacing: PixelHandTheme.Space.md) {
                                pointerPane(margin: 0, keyboardInDock: true)
                                sideColumn(plan: plan)
                            }
                        }
                    }
                case .screen:
                    dockedScreen(screenOnly: true)
                case .pointer:
                    HStack(spacing: PixelHandTheme.Space.md) {
                        pointerPane(margin: 0, keyboardInDock: true)
                            .floatingScreenTile(session: session)
                        sideColumn(plan: plan)
                    }
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, PixelHandTheme.Space.xs)
        }
        .safeAreaInset(edge: .bottom, spacing: PixelHandTheme.Space.sm) {
            VStack(spacing: PixelHandTheme.Space.sm) {
                stripOnly(metrics: metrics, foldedDock: false, margin: margin)
                HStack(spacing: PixelHandTheme.Space.md) {
                    dock
                    AskCircleButton(action: { openAsk(plan) })
                }
                .padding(.horizontal, margin)
            }
        }
    }

    /// iPad landscape and large Stage Manager windows.
    @ViewBuilder
    private func columnsLayout(plan: CanvasPlan) -> some View {
        let metrics = plan.metrics
        let preset = presetBinding(plan)
        HStack(alignment: .top, spacing: CGFloat(CanvasPlan.columnGap)) {
            if plan.showsSidebar {
                MacsSidebar(
                    currentMacName: peerName,
                    currentSubtitle: headerSubtitle,
                    isLive: isLive,
                    onCollapse: { sidebarCollapsed = true },
                    onOpenMacs: { isMyMacsPresented = true }
                )
                .transition(.opacity) // Glyph rule: panels fade, never slide.
            }

            // Centre column.
            VStack(spacing: PixelHandTheme.Space.md) {
                header(
                    presets: preset,
                    onAsk: { openAsk(plan) },
                    onShowSidebar: showSidebarAction(plan),
                    showsMirrorToggle: false,
                    horizontalPadding: 0
                )
                statusPills
                // With the column collapsed, the front app's shortcuts
                // move here, under the header.
                if !plan.stripInDeckColumn {
                    stripOnly(metrics: metrics, foldedDock: false, margin: 0)
                }
                centreCanvas(preset: preset.wrappedValue)
                    .padding(.bottom, CGFloat(CanvasPlan.floatingDockReserve))
                    .overlay(alignment: .bottom) {
                        dock
                            .frame(maxWidth: CGFloat(CanvasPlan.floatingDockMaximumWidth))
                            .padding(.bottom, PixelHandTheme.Space.lg)
                    }
            }
            .frame(maxWidth: .infinity)

            // Right column: Deck | Ask; Deck is the strip (a card while a
            // dialog is up) then the deck. Collapsed: the edge handle.
            wideColumn(plan: plan)
        }
        .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: rightColumn(plan).isCollapsed)
        .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: columnMode.wrappedValue)
        .padding(.leading, plan.showsSidebar ? 0 : CGFloat(metrics.margin))
        .padding(.trailing, CGFloat(metrics.margin))
        .padding(.bottom, PixelHandTheme.Space.sm)
    }

    /// The header's sidebar button, only while the sidebar could show but
    /// is collapsed.
    private func showSidebarAction(_ plan: CanvasPlan) -> (() -> Void)? {
        guard plan.canShowSidebar, !plan.showsSidebar else { return nil }
        return { sidebarCollapsed = false }
    }

    // MARK: - iPhone Duo (UX-040)

    /// The two panes around the crease, each at its exact frame so nothing
    /// lands in the band (`DuoPanes`). Each pane is a compact grid with the
    /// 16 pt margin on the screen edge and none toward the crease (the
    /// band holds the 20 pt clear on each side).
    @ViewBuilder
    private func duoLayout(plan: CanvasPlan, panes: DuoPanes) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if panes.pose == .book {
                    bookLeadingPane(panes: panes)
                } else {
                    laptopTopPane(panes: panes)
                }
            }
            .frame(width: CGFloat(panes.first.width), height: CGFloat(panes.first.height))
            .offset(x: CGFloat(panes.first.x), y: CGFloat(panes.first.y))

            Group {
                if panes.pose == .book {
                    bookTrailingPane(plan: plan, panes: panes)
                } else {
                    laptopBottomPane(plan: plan, panes: panes)
                }
            }
            .frame(width: CGFloat(panes.second.width), height: CGFloat(panes.second.height))
            .offset(x: CGFloat(panes.second.x), y: CGFloat(panes.second.y))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Book, leading pane: the selected tab picks the lead. Screen docks
    /// over the Pointer (handle between); Pointer fills the pane with the
    /// floating tile over it alone. The keyboard panel and app dock sit at
    /// the pane's foot.
    @ViewBuilder
    private func bookLeadingPane(panes: DuoPanes) -> some View {
        let outer = CGFloat(DuoPanes.outerMargin)
        VStack(spacing: PixelHandTheme.Space.md) {
            Group {
                switch DuoArrangement.bookLead(selected: selection.wrappedValue.rawValue) {
                case .screenOverPointer:
                    GeometryReader { proxy in
                        screenOverPane(size: proxy.size) {
                            pointerPane(margin: 0, keyboardInDock: true)
                        }
                    }
                case .pointer:
                    pointerPane(margin: 0, keyboardInDock: true)
                        .floatingScreenTile(session: session)
                }
            }
            .frame(maxHeight: .infinity)
            dock
                .padding(.horizontal, -PixelHandTheme.Space.md)
        }
        .padding(.leading, outer)
        .padding(.top, PixelHandTheme.Space.xs)
        .padding(.bottom, PixelHandTheme.Space.sm)
    }

    /// Book, trailing pane: header, status, the strip (wraps on compact),
    /// the deck at 4 a row, then the tab bar (Pointer, Screen) with Ask.
    @ViewBuilder
    private func bookTrailingPane(plan: CanvasPlan, panes: DuoPanes) -> some View {
        let outer = CGFloat(DuoPanes.outerMargin)
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
            header(horizontalPadding: 0)
            statusPills
            stripOnly(metrics: panes.secondMetrics, foldedDock: false, margin: 0)
            if let sender = session.sender {
                deck(sender: sender, columns: plan.deckColumnKeys, inset: 0)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            SurfaceTabBar(
                selection: selection,
                tabs: DuoArrangement.bookTabs.compactMap(ControlSurface.init(rawValue:)),
                onAsk: { openAsk(plan) }
            )
        }
        .padding(.trailing, outer)
        .padding(.bottom, PixelHandTheme.Space.sm)
    }

    /// Laptop, top pane: the header and the Mac's screen standing up above
    /// the crease.
    @ViewBuilder
    private func laptopTopPane(panes: DuoPanes) -> some View {
        let outer = CGFloat(DuoPanes.outerMargin)
        VStack(spacing: PixelHandTheme.Space.xs) {
            header(showsMirrorToggle: true, horizontalPadding: outer)
            statusPills
                .padding(.horizontal, outer)
            dockedScreen()
                .padding(.horizontal, outer)
                .frame(maxHeight: .infinity)
        }
    }

    /// Laptop, bottom pane: keyboard panel, the strip (running apps folded
    /// into its app chip), the Pointer or the Deck, and the tab bar.
    @ViewBuilder
    private func laptopBottomPane(plan: CanvasPlan, panes: DuoPanes) -> some View {
        let outer = CGFloat(DuoPanes.outerMargin)
        let showsDeck = DuoArrangement.laptopBottomShowsDeck(selected: selection.wrappedValue.rawValue)
        VStack(spacing: PixelHandTheme.Space.sm) {
            stripOnly(metrics: panes.secondMetrics, foldedDock: true, margin: outer)
            Group {
                if showsDeck, let sender = session.sender {
                    deck(sender: sender, columns: plan.deckColumnKeys, inset: outer)
                } else {
                    // The pad keeps its own keyboard circle: the dock is
                    // folded into the strip here.
                    pointerPane(margin: outer, keyboardInDock: false)
                }
            }
            .frame(maxHeight: .infinity)
            SurfaceTabBar(
                selection: selection,
                tabs: DuoArrangement.laptopTabs.compactMap(ControlSurface.init(rawValue:)),
                onAsk: { openAsk(plan) }
            )
            .padding(.horizontal, outer)
        }
        .padding(.bottom, PixelHandTheme.Space.sm)
    }

    // MARK: - Right column (OR-06)

    private var columnMode: Binding<RightColumnMode> {
        Binding(
            get: { RightColumnMode(rawValue: columnModeRawValue) ?? .deck },
            set: { columnModeRawValue = $0.rawValue }
        )
    }

    /// The right column for this plan, with its remembered collapsed state.
    private func rightColumn(_ plan: CanvasPlan) -> RightColumnPlan {
        let preset: LayoutPreset? = plan.usesPresets ? presetBinding(plan).wrappedValue : nil
        let arrangement = ArrangementPreset(plan: plan, preset: preset)
        let collapsed = RightColumnMemory(json: rightColumnJSON).isCollapsed(arrangement)
        return RightColumnPlan(plan: plan, preset: preset, collapsed: collapsed)
    }

    private func setCollapsed(_ collapsed: Bool, _ column: RightColumnPlan) {
        GestureHaptic.light.trigger()
        var memory = RightColumnMemory(json: rightColumnJSON)
        memory.set(collapsed, for: column.arrangement)
        rightColumnJSON = memory.json
    }

    /// Ask (⌘K, the Ask field or circle, the tab bar's Ask): in place in
    /// the right column where there is one (expanding it), else the sheet.
    private func openAsk(_ plan: CanvasPlan) {
        let column = rightColumn(plan)
        switch column.askRoute {
        case .column:
            var memory = RightColumnMemory(json: rightColumnJSON)
            memory.expandForAsk(column)
            rightColumnJSON = memory.json
            columnModeRawValue = RightColumnMode.ask.rawValue
            askFocusRequest += 1
        case .sheet:
            isAskPresented = true
        }
    }

    /// Ask in the column: the same panel and model as the sheet.
    private func askColumn(framed: Bool) -> some View {
        AskPanel(session: session, macName: peerName, placement: .column, focusRequest: askFocusRequest)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                framed ? PixelHandTheme.raised.opacity(0.5) : Color.clear,
                in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous))
    }

    /// iPad portrait's column beside the pad (Split and Pointer presets).
    @ViewBuilder
    private func sideColumn(plan: CanvasPlan) -> some View {
        let column = rightColumn(plan)
        Group {
            if column.isCollapsed {
                RightColumnHandle(mode: columnMode.wrappedValue) { setCollapsed(false, column) }
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                    RightColumnSwitch(mode: columnMode, canCollapse: column.canCollapse) { setCollapsed(true, column) }
                    Group {
                        if columnMode.wrappedValue == .ask {
                            askColumn(framed: true)
                        } else {
                            deckColumn(plan: plan)
                        }
                    }
                    .transition(.opacity)
                }
                .frame(width: CGFloat(column.expandedWidth))
                .transition(.opacity)
            }
        }
        .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: column.isCollapsed)
        .animation(Animation.phPanelFade(reduceMotion: reduceMotion), value: columnMode.wrappedValue)
    }

    /// iPad landscape's trailing column.
    @ViewBuilder
    private func wideColumn(plan: CanvasPlan) -> some View {
        let column = rightColumn(plan)
        if column.isCollapsed {
            RightColumnHandle(mode: columnMode.wrappedValue) { setCollapsed(false, column) }
                .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
                RightColumnSwitch(mode: columnMode, canCollapse: column.canCollapse) { setCollapsed(true, column) }
                    .frame(height: PixelHandTheme.ControlHeight.standard)
                Group {
                    if columnMode.wrappedValue == .ask {
                        askColumn(framed: true)
                    } else {
                        VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
                            stripCard(metrics: plan.metrics)
                            if let sender = session.sender {
                                deck(sender: sender, columns: plan.deckColumnKeys, inset: PixelHandTheme.Space.md)
                                    .background(PixelHandTheme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous))
                                    .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous))
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
            .frame(width: CGFloat(column.expandedWidth))
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
        }
    }

    // MARK: - Presets

    private func presetBinding(_ plan: CanvasPlan) -> Binding<LayoutPreset> {
        let key = plan.presetKey(macName: peerName)
        return Binding(
            get: { LayoutPresetMemory(json: presetMemoryJSON).preset(for: key) },
            set: { newValue in
                var memory = LayoutPresetMemory(json: presetMemoryJSON)
                memory.set(newValue, for: key)
                presetMemoryJSON = memory.json
            }
        )
    }

    /// The wide centre column's panes for the preset.
    @ViewBuilder
    private func centreCanvas(preset: LayoutPreset) -> some View {
        switch preset {
        case .split:
            GeometryReader { proxy in
                screenOverPane(size: proxy.size) {
                    pointerPane(margin: 0, keyboardInDock: true)
                }
            }
        case .screen:
            dockedScreen(screenOnly: true)
        case .pointer:
            pointerPane(margin: 0, keyboardInDock: true)
                .floatingScreenTile(session: session)
        }
    }

    /// The docked screen over `lower`, split by a drag handle. When both
    /// can't fit (`PaneSplit` says nil), the lower pane shows alone with the
    /// floating tile over it.
    @ViewBuilder
    private func screenOverPane<Lower: View>(size: CGSize, @ViewBuilder lower: () -> Lower) -> some View {
        let total = Double(size.height)
        let stored: Double? = screenShare > 0 ? screenShare : nil
        let fraction = dragSize.map { Double($0) / max(total, 1) } ?? stored
        if let screen = PaneSplit.screenHeight(
            total: total,
            width: Double(size.width),
            aspect: Double(MirrorPicture.aspect(session)),
            fraction: fraction
        ) {
            VStack(spacing: 0) {
                dockedScreen()
                    .frame(height: CGFloat(screen))
                PaneDragHandle(
                    onDrag: { delta in dragSize = (dragSize ?? CGFloat(screen)) + delta },
                    onEnd: {
                        if let dragSize { screenShare = PaneSplit.fraction(screenHeight: Double(dragSize), total: total) }
                        dragSize = nil
                    },
                    onAdjust: { grow in
                        let step = total * 0.1
                        let next = screen + (grow ? step : -step)
                        screenShare = PaneSplit.fraction(screenHeight: next, total: total)
                    },
                    label: "Resize the screen"
                )
                .frame(height: CGFloat(PaneSplit.gap))
                lower()
                    .frame(maxHeight: .infinity)
            }
        } else {
            lower()
                .floatingScreenTile(session: session)
        }
    }

    /// The Mac's screen as a pane (or its "Show screen" empty state).
    /// `screenOnly`: no pad beside it, so the pane offers pointer control
    /// on the picture (OR-16).
    private func dockedScreen(screenOnly: Bool = false) -> some View {
        ScreenSurface(session: session, macName: peerName, includesTrackpad: false, screenOnly: screenOnly)
    }

    @ViewBuilder
    private func pointerPane(margin: CGFloat, keyboardInDock: Bool) -> some View {
        if let sender = session.sender {
            PointerSurface(
                sender: sender,
                clipboard: session.clipboard,
                margin: margin,
                keyboardInDock: keyboardInDock
            )
        } else {
            connectingSurface
        }
    }

    // MARK: - Stacked (½ Split View)

    /// The selected surface over the deck panel, split by a handle. The
    /// panel opens at one row of keys and never squeezes the pad below its
    /// minimum; without room it goes and the deck stays a tab.
    @ViewBuilder
    private func stackedCanvas(centre: ControlSurface, plan: CanvasPlan) -> some View {
        let metrics = plan.metrics
        GeometryReader { proxy in
            let total = Double(proxy.size.height)
            let keySize = metrics.deckGrid.keySize
            let requested = dragSize.map { Double($0) } ?? (deckPanelHeight > 0 ? deckPanelHeight : 0)
            if let sender = session.sender,
               let panel = DeckPanelSplit.height(total: total, requested: requested, keySize: keySize) {
                VStack(spacing: 0) {
                    canvas(centre: centre, plan: plan)
                        .frame(maxHeight: .infinity)
                    PaneDragHandle(
                        onDrag: { delta in dragSize = (dragSize ?? CGFloat(panel)) - delta },
                        onEnd: {
                            if let dragSize { deckPanelHeight = Double(dragSize) }
                            dragSize = nil
                        },
                        onAdjust: { grow in
                            // "Increment" grows the surface above, so the panel shrinks.
                            let step = DeckPanelSplit.panelHeight(rows: 1, keySize: keySize) - DeckPanelSplit.headerHeight
                            deckPanelHeight = max(0, panel + (grow ? -step : step))
                        },
                        label: "Resize the deck"
                    )
                    .frame(height: CGFloat(DeckPanelSplit.gap))
                    deck(sender: sender, columns: plan.deckColumnKeys, inset: CGFloat(metrics.margin))
                        .frame(height: CGFloat(panel))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Deck")
                }
            } else {
                canvas(centre: centre, plan: plan)
            }
        }
    }

    // MARK: - Strip, keyboard and dock (UX-005)

    private var appsByID: [String: InstalledAppInfo] {
        InstalledAppInfo.byBundleID(session.installedApps)
    }

    private var frontApp: InstalledAppInfo? {
        session.activeBundleID.flatMap { appsByID[$0] }
    }

    private var frontHasDialog: Bool {
        if case .dialog = session.uiContext { return true }
        return false
    }

    private var dockEntries: [AppDockEntry] {
        AppDockPlan.entries(
            order: dockOrder,
            known: Set(appsByID.keys),
            front: session.activeBundleID,
            frontHasDialog: frontHasDialog
        )
    }

    private func stripMode(metrics: LayoutMetrics) -> ContextStripPlan.Mode {
        ContextStripPlan.mode(
            context: session.uiContext,
            hasFrontApp: frontApp != nil,
            widthClass: metrics.widthClass,
            allowsAppChips: entitlements.allows(.decks)
        )
    }

    /// single / stacked: keyboard panel, strip and dock (or the strip with
    /// the dock folded into it on short windows).
    @ViewBuilder
    private func bottomChrome(metrics: LayoutMetrics, foldsDock: Bool) -> some View {
        // The strip and dock stay put while typing: the Type panel is laid
        // over the shell, above the keyboard (OT-2).
        VStack(spacing: PixelHandTheme.Space.sm) {
            stripOnly(metrics: metrics, foldedDock: foldsDock, margin: CGFloat(metrics.margin))
            if !foldsDock {
                dock
            }
        }
        .frame(maxWidth: 720)
    }

    /// Whether this form shows the app dock (the Type panel sits above it
    /// when no keyboard covers it). The rail and the Duo laptop pose fold
    /// it into the strip, and so do short single and stacked windows.
    private func showsDock(_ plan: CanvasPlan) -> Bool {
        switch plan.form {
        case .rail, .laptop: false
        case .single, .stacked: CGFloat(plan.metrics.height) >= Self.foldedDockHeight
        case .sideBySide, .columns, .book: true
        }
    }

    /// The context strip. `foldedDock` puts the running apps in its leading
    /// app chip (short windows and the landscape rail have no dock row).
    @ViewBuilder
    private func stripOnly(metrics: LayoutMetrics, foldedDock: Bool, margin: CGFloat) -> some View {
        if let sender = session.sender {
            let apps = appsByID
            ContextStrip(
                sender: sender,
                mode: stripMode(metrics: metrics),
                frontApp: frontApp,
                bindings: session.activeBundleID.map { shortcuts.bindings(for: $0) } ?? [],
                foldedApps: foldedDock ? dockEntries.compactMap { apps[$0.bundleID] } : nil,
                margin: margin,
                onOpenAppSheet: { shortcutsApp = $0 },
                onActivate: { app in Task { await sender.sendLaunchApp(app.bundleID) } }
            )
            .id(stripIdentity)
            .transition(.opacity)
            .animation(PixelHandMotion.reduced(PixelHandMotion.standard, reduceMotion: reduceMotion), value: stripIdentity)
        }
    }

    /// The wide deck column's strip: a raised card (radius 24, 12 inset)
    /// while the Mac shows a dialog, the plain row otherwise. Board:
    /// `v2PadLand` `.dlgcard`.
    @ViewBuilder
    private func stripCard(metrics: LayoutMetrics) -> some View {
        if frontHasDialog {
            stripOnly(metrics: metrics, foldedDock: false, margin: PixelHandTheme.Space.md)
                .padding(.vertical, PixelHandTheme.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                        .fill(PixelHandTheme.raised)
                        .overlay(
                            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                                .strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
                        )
                )
        } else {
            stripOnly(metrics: metrics, foldedDock: false, margin: 0)
        }
    }

    @ViewBuilder
    private var dock: some View {
        if let sender = session.sender {
            AppDock(
                entries: dockEntries,
                apps: appsByID,
                isKeyboardShown: typePanel.isShown,
                onActivate: { app in Task { await sender.sendLaunchApp(app.bundleID) } },
                onShortcuts: { shortcutsApp = $0 },
                onHide: { app in Task { _ = await sender.sendConfirmed(.appShortcut(bundleID: app.bundleID, keys: ["cmd", "h"])) } },
                onQuit: { app in Task { _ = await sender.sendConfirmed(.appShortcut(bundleID: app.bundleID, keys: ["cmd", "q"])) } },
                onKeyboard: { typePanel.toggle() }
            )
            .padding(.horizontal, PixelHandTheme.Space.md)
            // With a hardware or minimised keyboard, iPadOS's slim bar
            // (language, Paste, dictation) sits at the bottom: the dock
            // rides on it instead of under it (OT-11).
            .padding(.bottom, CGFloat(typePanel.dockLift))
            .animation(PixelHandMotion.quick, value: typePanel.dockLift)
            // The Type panel sits above the dock when no keyboard covers it.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { typePanel.dockMinY = $0 }
        }
    }

    /// Changes when the strip's content changes kind, so it cross-fades
    /// instead of morphing chip by chip.
    private var stripIdentity: String {
        switch session.uiContext {
        case .dialog(let dialog): "dialog-\(dialog.revision)"
        case .textField(let field): "field-\(session.activeBundleID ?? "")-\(field.kind.rawValue)"
        case .none: "app-\(session.activeBundleID ?? "")"
        }
    }

    // MARK: - Header and status

    private func header(
        presets: Binding<LayoutPreset>? = nil,
        onAsk: (() -> Void)? = nil,
        onShowSidebar: (() -> Void)? = nil,
        showsMirrorToggle: Bool = true,
        horizontalPadding: CGFloat = PixelHandTheme.Space.lg
    ) -> some View {
        ShellHeader(
            peerName: peerName,
            subtitle: headerSubtitle,
            isLive: isLive,
            isLocked: session.macLockState.bannerText(macName: peerName) != nil,
            link: RemoteLinkStatus.shared.current,
            isMirrorActive: session.isMirrorActive,
            isCaptureBusy: session.capture.isRequestingScreenshot,
            onToggleMirror: { session.toggleMirror(settings: settings) },
            onFullScreen: { session.capture.beginCapture(intent: .fullScreen, mode: .fullScreen, quality: settings.screenshotQuality) },
            onRegion: { session.capture.beginCapture(intent: .regionPicking, mode: .fullScreen, quality: settings.screenshotQuality) },
            onWindow: { session.capture.openWindowPicker() },
            onOCR: { session.capture.beginCapture(intent: .ocr, mode: .fullScreen, quality: settings.screenshotQuality) },
            onPrimaryCapture: { session.capture.beginDefaultCapture(settings: settings) },
            onMacs: { isMyMacsPresented = true },
            onSettings: onSettings,
            onClassicLayout: onClassicLayout,
            onDisconnect: onDisconnect,
            presets: presets,
            onAsk: onAsk,
            onShowSidebar: onShowSidebar,
            showsMirrorToggle: showsMirrorToggle,
            horizontalPadding: horizontalPadding
        )
    }

    /// Host permission and lock warnings: the Mac reports what it can do, so
    /// a missing permission shows here instead of taps failing silently.
    private var statusPills: some View { statusPills(offersKeyboard: true) }

    /// `offersKeyboard`: the lock banner's Keyboard button opens the shell's
    /// keyboard panel, so it shows only where that panel can (not the rail).
    @ViewBuilder
    private func statusPills(offersKeyboard: Bool) -> some View {
        VStack(spacing: PixelHandTheme.Space.sm) {
            if session.hostAccessibilityGranted == false {
                StatusPill(
                    title: "\(peerName) needs Accessibility.",
                    message: "Mouse, keyboard and shortcuts won’t work until you allow it in Pixel Hand’s menu on the Mac."
                )
            }
            if let lockText = session.macLockState.bannerText(macName: peerName) {
                if offersKeyboard, session.macLockState == .screenLocked {
                    StatusPill(kind: .locked, message: lockText, fixTitle: "Keyboard") {
                        GestureHaptic.light.trigger()
                        typePanel.open()
                    }
                } else {
                    StatusPill(kind: .locked, message: lockText)
                }
            }
            if session.hostScreenRecordingGranted == false {
                StatusPill(
                    title: "\(peerName) needs Screen Recording.",
                    message: "Screenshots and the live screen won’t work until you allow it on the Mac."
                )
            }
        }
        .transition(.opacity)
    }

    // MARK: - Canvas (one surface)

    /// One surface: single, stacked's upper pane, and the rail's pad.
    @ViewBuilder
    private func canvas(centre: ControlSurface, plan: CanvasPlan, margin: CGFloat? = nil) -> some View {
        let margin = margin ?? CGFloat(plan.metrics.margin)
        ZStack {
            if let sender = session.sender {
                // UX-017: surfaces swap with the pixel dissolve (a fade
                // under Reduce Motion).
                surfaceView(centre, sender: sender, plan: plan, margin: margin)
                    .id(centre)
                    .transition(.pixelDissolve(reduceMotion: reduceMotion, isCompact: horizontalSizeClass == .compact))
            } else {
                connectingSurface
                    .padding(.horizontal, margin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Connecting → connected powers the surface on.
        .powerOn(when: session.sender != nil)
        .animation(PixelHandMotion.dissolve(reduceMotion: reduceMotion), value: centre)
        // The floating screen tile on Pointer and Deck (the Screen surface
        // docks it in its own pane).
        .floatingScreenTile(session: session, isShown: centre != .screen)
    }

    private var connectingSurface: some View {
        PixelSurface {
            VStack(spacing: PixelHandTheme.Space.lg) {
                DotWave(label: "Connecting to \(peerName)")
                DotMatrixText("CONNECTING", pitch: 1.6, label: "Connecting")
                    .foregroundStyle(PixelHandTheme.Brand.phosphor)
            }
        }
    }

    @ViewBuilder
    private func surfaceView(_ surface: ControlSurface, sender: TrackpadSender, plan: CanvasPlan, margin: CGFloat) -> some View {
        switch surface {
        case .pointer:
            PointerSurface(
                sender: sender,
                clipboard: session.clipboard,
                margin: margin,
                // The dock carries the keyboard button wherever it shows.
                keyboardInDock: dockCarriesKeyboard(plan)
            )
        case .screen:
            ScreenSurface(session: session, macName: peerName, keyboardInDock: dockCarriesKeyboard(plan), screenOnly: true)
                .padding(.horizontal, margin)
                .padding(.bottom, PixelHandTheme.Space.sm)
        case .deck:
            deck(sender: sender, columns: plan.metrics.deckColumns, inset: margin)
        }
        // (The strip and dock live in the shell's chrome, so the deck hides
        // its own Quick Actions bar and edit buttons.)
    }

    /// Whether the app dock shows (and so carries the keyboard button), or
    /// the rail does (iPhone landscape, VQ-105): either way the pad leaves
    /// its own button out, so there's one per window.
    private func dockCarriesKeyboard(_ plan: CanvasPlan) -> Bool {
        plan.railCarriesKeyboard
            || (!plan.foldsDockIntoStrip && CGFloat(plan.metrics.height) >= Self.foldedDockHeight)
    }

    // MARK: - Deck

    /// The deck beside the pad (iPad portrait): 3 keys a row, in the
    /// 300 pt right column (`sideColumn` sets the width).
    @ViewBuilder
    private func deckColumn(plan: CanvasPlan) -> some View {
        if let sender = session.sender {
            deck(sender: sender, columns: plan.deckColumnKeys, inset: PixelHandTheme.Space.md)
                .background(PixelHandTheme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.pane, style: .continuous))
        } else {
            Color.clear
        }
    }

    private func deck(sender: TrackpadSender, columns: Int, inset: CGFloat) -> some View {
        // Deck 2 UI (UX-020): DeckSurface sizes its own grid from the space it
        // gets (DeckGrid.pane), so the arrangement's column hint is advisory;
        // the inset still applies.
        _ = columns
        return DeckSurface(session: session, sender: sender)
            .padding(.horizontal, inset)
    }
}

// MARK: - Floating screen tile

private struct FloatingScreenTile: ViewModifier {
    let session: ControlSessionModel
    let isShown: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                // Laid over this pane alone, so the tile's 120 pt band
                // (`MirrorThumbnailView`) lines up with the pad's foot.
                GeometryReader { proxy in
                    if isShown && session.isMirrorActive {
                        MirrorOverlay(session: session, containerSize: proxy.size)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.2), value: session.isMirrorActive)
    }
}

private extension View {
    func floatingScreenTile(session: ControlSessionModel, isShown: Bool = true) -> some View {
        modifier(FloatingScreenTile(session: session, isShown: isShown))
    }
}
