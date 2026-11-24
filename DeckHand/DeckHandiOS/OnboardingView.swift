//
//  OnboardingView.swift
//  DeckHandiOS
//
//  First-run walkthrough: what the app is, the three things it does, and the
//  one step on the Mac. Every page has its own dot-art scene on the navy
//  plate, glyph bullets, a dot-matrix step counter and Back / Continue.
//  Two columns (scene left, text right) when `LayoutMetrics` says so: iPad
//  landscape, large Stage Manager windows and iPhone landscape; on an open
//  iPhone Duo, the scene on one pane and the text on the other. Content
//  scrolls, so nothing clips at AX sizes or in landscape; at AX sizes the
//  buttons scroll after the text. Body copy is leading-aligned.
//  Spec: `Product/Design/06-Pixel-Identity.md` §9, `04-Interaction-Model.md` §5.
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page = 0
    /// +1 going forward, -1 going back: picks the text's slide direction.
    @State private var direction = 1
    /// The iPhone Duo's hinge (iOS 27.1+), for the two-pane layout.
    @State private var hingeStatus: DuoHingeStatus?

    private let pages = OnboardingPage.all
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(width: proxy.size.width, height: proxy.size.height)
            let twoColumns = metrics.usesTwoColumnPages
            let crease = DuoPoseMachine.band(for: DuoCrease.input(proxy: proxy, hingeStatus: hingeStatus))
            Group {
                if let crease {
                    // iPhone Duo open: nothing on the crease (VQ-067).
                    duoPage(band: crease, size: proxy.size, metrics: metrics)
                } else {
                    VStack(spacing: 0) {
                        topBar(metrics: metrics)
                        if twoColumns {
                            twoColumnPage(metrics: metrics, size: proxy.size)
                        } else {
                            singleColumnPage(metrics: metrics, size: proxy.size)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
        }
        .duoHingeStatus($hingeStatus)
        .background(PixelHandTheme.brandBackground().ignoresSafeArea())
        .foregroundStyle(.white)
        .pixelOnNavy()
        .preferredColorScheme(.dark)
    }

    // MARK: - Layouts

    /// Phones in portrait, iPad portrait and Split View: scene, text and
    /// bullets scroll; dots and buttons stay pinned at the bottom. At
    /// accessibility sizes the dots and buttons scroll after the text, so
    /// the text never runs under them (VQ-064, `07-Polish-Spec.md` §6).
    /// Body copy and bullets are leading-aligned under a leading-aligned
    /// title; only the scene is centred (VQ-019, §5.8).
    private func singleColumnPage(metrics: LayoutMetrics, size: CGSize) -> some View {
        let isRoomy = metrics.widthClass != .compact
        let nominal: CGFloat = isRoomy ? 340 : 248
        // Keeps the scene from pushing the title off a short screen.
        let scene = min(nominal, max(168, (size.height * 0.34).rounded()))
        let textWidth: CGFloat = isRoomy ? 520 : 340
        let controlsScroll = typeSize.isAccessibilitySize
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: isRoomy ? 40 : 28) {
                    sceneView(size: scene)
                    VStack(alignment: .leading, spacing: isRoomy ? 28 : 20) {
                        text(alignment: .leading, maxWidth: textWidth, roomy: isRoomy)
                        bullets(alignment: .leading)
                    }
                    .frame(maxWidth: textWidth, alignment: .leading)
                    .modifier(PageTextTransition(page: page, direction: direction, reduceMotion: reduceMotion))
                    if controlsScroll {
                        controls(roomy: isRoomy)
                    }
                }
                .padding(.horizontal, isRoomy ? 48 : 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(0, size.height - (controlsScroll ? 0 : bottomReserve(roomy: isRoomy)) - 44), alignment: .center)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            if !controlsScroll {
                controls(roomy: isRoomy)
                    .padding(.horizontal, isRoomy ? 48 : 24)
                    .padding(.top, 12)
                    .padding(.bottom, isRoomy ? 24 : 8)
            }
        }
    }

    private func controls(roomy: Bool) -> some View {
        VStack(spacing: roomy ? 24 : 16) {
            PageDots(count: pages.count, current: page)
            buttons(maxWidth: 420)
        }
    }

    /// iPhone Duo open: the scene on the first pane, the text, dots and
    /// buttons on the second, each pane meeting the crease band (which
    /// holds the 20 pt clear on each side) and never crossing it.
    private func duoPage(band: DuoCreaseBand, size: CGSize, metrics: LayoutMetrics) -> some View {
        let panes = DuoPanes(width: Double(size.width), height: Double(size.height), band: band)
        let first = panes.first
        let second = panes.second
        let scene = min(248, max(160, CGFloat(min(first.width, first.height)) - 48))
        return ZStack(alignment: .topLeading) {
            sceneView(size: scene)
                .frame(width: CGFloat(first.width), height: CGFloat(first.height))
                .offset(x: CGFloat(first.x), y: CGFloat(first.y))
            VStack(spacing: 0) {
                topBar(metrics: panes.secondMetrics)
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        text(alignment: .leading, maxWidth: 400, roomy: false)
                        bullets(alignment: .leading)
                    }
                    .modifier(PageTextTransition(page: page, direction: direction, reduceMotion: reduceMotion))
                    PageDots(count: pages.count, current: page)
                    buttons(maxWidth: 400)
                }
                .padding(panes.pose == .book ? .trailing : .horizontal, CGFloat(DuoPanes.outerMargin))
                .padding(.vertical, 16)
                .frame(minHeight: max(0, CGFloat(second.height) - 48), alignment: .center)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(width: CGFloat(second.width), height: CGFloat(second.height))
            .offset(x: CGFloat(second.x), y: CGFloat(second.y))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// iPad landscape and iPhone landscape: scene left, a left-aligned text
    /// column right with the dots and buttons under the text.
    private func twoColumnPage(metrics: LayoutMetrics, size: CGSize) -> some View {
        let isWide = metrics.widthClass == .wide
        let scene: CGFloat = isWide ? 400 : min(248, max(168, size.height - 120))
        let textWidth: CGFloat = isWide ? 440 : 400
        return ScrollView {
            HStack(alignment: .center, spacing: isWide ? 72 : 40) {
                sceneView(size: scene)
                VStack(alignment: .leading, spacing: isWide ? 28 : 18) {
                    VStack(alignment: .leading, spacing: isWide ? 28 : 18) {
                        text(alignment: .leading, maxWidth: textWidth, roomy: isWide)
                        bullets(alignment: .leading)
                    }
                    .modifier(PageTextTransition(page: page, direction: direction, reduceMotion: reduceMotion))
                    PageDots(count: pages.count, current: page)
                        .padding(.top, 4)
                    buttons(maxWidth: textWidth)
                }
                .frame(maxWidth: textWidth, alignment: .leading)
            }
            .padding(.horizontal, isWide ? 72 : 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(0, size.height - 44), alignment: .center)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func bottomReserve(roomy: Bool) -> CGFloat {
        // Dots + one button row (two at AX sizes) + padding.
        (typeSize.isAccessibilitySize ? 140 : 84) + (roomy ? 48 : 24)
    }

    // MARK: - Pieces

    private func topBar(metrics: LayoutMetrics) -> some View {
        HStack(spacing: 10) {
            DotMatrixText(
                String(format: "%02d/%02d", page + 1, pages.count),
                pitch: 1.6,
                label: "Step \(page + 1) of \(pages.count)"
            )
            .foregroundStyle(PixelHandTheme.Brand.phosphor)
            .contentTransition(.identity)
            Spacer()
            Button("Skip") { onFinish() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 44, minHeight: 44)
                // Hidden rather than removed on the last page so the bar
                // keeps its height.
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
                .accessibilityHidden(isLast)
                .accessibilityHint("Skips the tour")
                .accessibilityIdentifier("ph.onboarding.skip")
        }
        .padding(.horizontal, metrics.widthClass == .compact ? 20 : 32)
        .frame(minHeight: 44)
        .padding(.top, 4)
    }

    private func sceneView(size: CGFloat) -> some View {
        // A ZStack so the outgoing and incoming scenes overlap while the
        // pixel dissolve runs instead of stacking.
        ZStack {
            OnboardingSceneView(scene: pages[page].scene, size: size)
                .id(page)
                .transition(reduceMotion ? .opacity : .pixelDissolve)
        }
        .frame(width: size, height: size)
        .background {
            if pages[page].scene != .mark {
                OnboardingSceneGlow(size: size)
            }
        }
    }

    private func text(alignment: TextAlignment, maxWidth: CGFloat, roomy: Bool) -> some View {
        let item = pages[page]
        return VStack(alignment: alignment == .leading ? .leading : .center, spacing: 12) {
            Text(item.title)
                .font(PixelHandFonts.geist(.medium, size: roomy ? 40 : 30, relativeTo: .largeTitle))
                .tracking(roomy ? -1 : -0.8)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("ph.onboarding.title")
            Text(item.body)
                .font(.body)
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(2)
        }
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: maxWidth, alignment: alignment == .leading ? .leading : .center)
    }

    @ViewBuilder
    private func bullets(alignment: HorizontalAlignment) -> some View {
        let item = pages[page]
        if !item.bullets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(item.bullets) { bullet in
                    OnboardingBulletRow(bullet: bullet)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        }
    }

    private func buttons(maxWidth: CGFloat) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if typeSize.isAccessibilitySize {
                continueButton
                if page > 0 { backButton.frame(maxWidth: .infinity) }
            } else {
                if page > 0 { backButton.frame(width: 120) }
                continueButton
            }
        }
        .frame(maxWidth: maxWidth)
    }

    private var backButton: some View {
        Button {
            go(to: page - 1)
        } label: {
            Text("Back").frame(maxWidth: .infinity)
        }
        .buttonStyle(.ph(.secondary))
        .accessibilityIdentifier("ph.onboarding.back")
    }

    private var continueButton: some View {
        Button {
            if isLast { onFinish() } else { go(to: page + 1) }
        } label: {
            Text(isLast ? "Find my Mac" : page == 0 ? "Get started" : "Continue")
        }
        .buttonStyle(.ph(.primary, fullWidth: true))
        .shadow(color: PixelHandTheme.Brand.cobalt.opacity(0.45), radius: 16, y: 6)
        .accessibilityIdentifier("ph.onboarding.continue")
    }

    // MARK: - Paging

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                if dx < 0, !isLast { go(to: page + 1) }
                if dx > 0, page > 0 { go(to: page - 1) }
            }
    }

    private func go(to index: Int) {
        guard pages.indices.contains(index), index != page else { return }
        direction = index > page ? 1 : -1
        withAnimation(reduceMotion ? PixelHandMotion.reducedFade : .easeOut(duration: 0.3)) {
            page = index
        }
    }
}

// MARK: - Page model

struct OnboardingPage: Identifiable {
    struct Bullet: Identifiable {
        let glyph: GlyphBitmap
        let text: String
        var id: String { text }
    }

    let scene: OnboardingScene
    let title: String
    let body: String
    /// Glyph rows under the text. Empty on the welcome page.
    let bullets: [Bullet]

    var id: OnboardingScene { scene }

    static let all: [OnboardingPage] = [
        OnboardingPage(
            scene: .mark,
            title: "Pixel Hand",
            body: "Your iPhone or iPad becomes a trackpad, a live view of your Mac and a set of buttons for the app in front. Over your own network, with nothing in between.",
            bullets: []
        ),
        OnboardingPage(
            scene: .trackpad,
            title: "A real trackpad",
            body: "Move, click and scroll with the gestures you already know. The dots light up under your fingers.",
            bullets: [
                Bullet(glyph: PixelGlyphs.click, text: "Two fingers to scroll"),
                Bullet(glyph: PixelGlyphs.missionControl, text: "Three fingers to switch desktops"),
                Bullet(glyph: PixelGlyphs.pointer, text: "Tap, then hold to drag"),
            ]
        ),
        OnboardingPage(
            scene: .mirror,
            title: "Watch your Mac",
            body: "Keep a live view of the screen next to the trackpad. Pinch it bigger to read, flick it to a corner when you’re done.",
            bullets: [
                Bullet(glyph: PixelGlyphs.pictureInPicture, text: "Drag it anywhere"),
                Bullet(glyph: PixelGlyphs.region, text: "Pinch to resize"),
                Bullet(glyph: PixelGlyphs.screen, text: "Gets sharper as it grows"),
            ]
        ),
        OnboardingPage(
            scene: .capture,
            title: "Capture and read",
            body: "Take the whole screen, one window or a region. Mark it up, or lift the text straight out of it.",
            bullets: [
                Bullet(glyph: PixelGlyphs.capture, text: "Full screen, window or region"),
                Bullet(glyph: PixelGlyphs.type, text: "Mark up before you share"),
                Bullet(glyph: PixelGlyphs.readText, text: "Copy the text from any capture"),
            ]
        ),
        OnboardingPage(
            scene: .pairing,
            title: "One step on your Mac",
            body: "Open Pixel Hand on your Mac. The first time you connect, you pair once with a code from its menu bar.",
            bullets: [
                Bullet(glyph: PixelGlyphs.mac, text: "Free at pixelhand.app/mac"),
                Bullet(glyph: PixelGlyphs.wifi, text: "Same Wi-Fi, or a cable"),
                Bullet(glyph: PixelGlyphs.lock, text: "Pair once with a code"),
            ]
        ),
    ]
}

// MARK: - Button style

/// Press feedback for the primary calls to action. Subtle scale, quick
/// release — the button should feel like it heard the tap immediately.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

#Preview("Onboarding · iPhone") {
    OnboardingView {}
}
