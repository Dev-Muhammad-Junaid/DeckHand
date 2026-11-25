//
//  PairDeviceWindow.swift
//  DeckHandMac
//
//  The "Pair a device" window (UX-012, board `v2PairMac`): the QR code in
//  dots with the icon's hand tile on its centre module (OR-10), the code in dot-matrix
//  numerals (two groups of four, all at full brightness) and a dot beam counting
//  down the 5-minute window. Opened from the menu-bar panel's "Pair a
//  device" and a pending request's "Pair". Closing it cancels the code.
//  The code window itself is `DeviceAuthorizationManager`'s (S4).
//

import AppKit
import SwiftUI

@MainActor
final class PairDeviceWindow: NSObject, NSWindowDelegate {
    static let shared = PairDeviceWindow()

    private var window: NSWindow?
    private weak var authManager: DeviceAuthorizationManager?

    /// Shows a new code (unless one is already showing) and brings the
    /// window forward.
    func open(_ authManager: DeviceAuthorizationManager) {
        self.authManager = authManager
        if case .code = authManager.pairingDisplay {} else {
            authManager.showPairingCode()
        }
        let window = self.window ?? makeWindow(authManager)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window (Cancel, or after a successful pairing).
    func close() {
        window?.close()
    }

    var isOpen: Bool { window?.isVisible ?? false }

    private func makeWindow(_ authManager: DeviceAuthorizationManager) -> NSWindow {
        let hosting = NSHostingController(
            rootView: PairDeviceView(onClose: { [weak self] in self?.close() })
                .environmentObject(authManager)
        )
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Pair a device"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setAccessibilityIdentifier("ph.mac.pairDeviceWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let authManager else { return }
        switch authManager.pairingDisplay {
        case .code, .paired: authManager.cancelPairingCode()
        case .none, .lockedOut: break
        }
    }
}

// MARK: - View

struct PairDeviceView: View {
    let onClose: () -> Void

    @EnvironmentObject private var authManager: DeviceAuthorizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: PixelHandTheme.Space.xl) {
            qr
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
                content
            }
            .frame(width: 280, alignment: .leading)
        }
        .padding(.horizontal, PixelHandTheme.Space.xl + 4)
        .padding(.vertical, PixelHandTheme.Space.xl)
        .frame(minWidth: 560, minHeight: 300)
        .background(PixelHandTheme.canvas)
        .onReceive(ticker) { _ in authManager.refreshPairingDisplay() }
    }

    // MARK: QR

    @ViewBuilder private var qr: some View {
        let side: CGFloat = 184
        switch authManager.pairingDisplay {
        case .code:
            if let invite = authManager.pairingInvite, let matrix = QRMatrix.make(invite.payload) {
                QRDotsView(matrix: matrix, side: side)
                    .transition(.opacity)
            } else {
                placeholder(side: side, glyph: PixelGlyphs.pointer)
            }
        case .paired:
            placeholder(side: side, glyph: PixelGlyphs.iPhone, lit: true)
        case .lockedOut:
            placeholder(side: side, glyph: PixelGlyphs.lock)
        case .none:
            placeholder(side: side, glyph: PixelGlyphs.pointer, lit: false)
        }
    }

    private func placeholder(side: CGFloat, glyph: GlyphBitmap, lit: Bool = true) -> some View {
        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
            .fill(PixelHandTheme.Brand.screenSurface)
            .overlay(MacGlyphTile(glyph: glyph, size: 96, pitch: 6, isLit: lit))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    // MARK: Text column

    @ViewBuilder private var content: some View {
        switch authManager.pairingDisplay {
        case let .code(code, expiresAt, attemptsLeft):
            // One line: "or iPad" used to wrap alone (VQ-022).
            title("Scan with your iPhone or iPad", singleLine: true)
            Text("Or open Pixel Hand there, choose \(Self.macName) and type the code.")
                .font(.body)
                .foregroundStyle(PixelHandTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            codePlate(code)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = expiresAt.timeIntervalSince(context.date)
                HStack(spacing: PixelHandTheme.Space.sm) {
                    MacDotBeam(lit: PairingCodeDisplay.beamLitCells(remaining: remaining))
                    Text("Works once, for \(PairingCodeDisplay.countdown(remaining: remaining))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(PixelHandTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Code expires in \(PairingCodeDisplay.spokenCountdown(remaining: remaining))")
            }
            if attemptsLeft < PairingCodeWindow.maxWrongAttempts {
                let wrong = PairingCodeWindow.maxWrongAttempts - attemptsLeft
                Text("\(wrong) wrong \(wrong == 1 ? "code" : "codes") entered. \(attemptsLeft) left.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PixelHandTheme.warning)
            }
            HStack(spacing: PixelHandTheme.Space.sm) {
                Button("New code") { authManager.showPairingCode() }
                    .buttonStyle(.macSecondary)
                    .help("Replace this code with a new one. The old code stops working.")
                    .accessibilityLabel("Make a new code")
                    .accessibilityIdentifier("ph.mac.newCode")
                Button("Cancel") {
                    authManager.cancelPairingCode()
                    onClose()
                }
                .buttonStyle(.macSecondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel pairing")
                .accessibilityIdentifier("ph.mac.cancelPairing")
            }
            .padding(.top, PixelHandTheme.Space.xs)

        case .paired:
            title("Paired")
            Text("It connects without asking from now on. Forget it in the menu bar panel to undo.")
                .font(.body)
                .foregroundStyle(PixelHandTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PixelHandTheme.Space.sm) {
                MacStatusPixel(color: PixelHandTheme.success, size: 8, breathes: true)
                MacDotText("PAIRED", pitch: 2, label: "Paired")
                    .foregroundStyle(PixelHandTheme.success)
            }
            .task {
                try? await Task.sleep(for: .seconds(2))
                onClose()
            }

        case let .lockedOut(until):
            title("Pairing is paused")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(1, Int(until.timeIntervalSince(context.date).rounded(.up)))
                Text("Too many wrong codes. Try again in \(ApprovalStatusCopy.durationText(seconds: left)).")
                    .font(.body)
                    .foregroundStyle(PixelHandTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Close", action: onClose)
                .buttonStyle(.macSecondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("ph.mac.closePairing")

        case .none:
            title("The code has expired")
            Text("Codes work for five minutes. Make a new one when the device is ready.")
                .font(.body)
                .foregroundStyle(PixelHandTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PixelHandTheme.Space.sm) {
                Button("New code") { authManager.showPairingCode() }
                    .buttonStyle(.macPrimary)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Make a new code")
                    .accessibilityIdentifier("ph.mac.newCode")
                Button("Close", action: onClose)
                    .buttonStyle(.macSecondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("ph.mac.closePairing")
            }
        }
    }

    @ViewBuilder
    private func title(_ text: String, singleLine: Bool = false) -> some View {
        let base = Text(text)
            .font(.phDisplay(.title2))
            .tracking(PixelHandTheme.TextRole.display.tracking)
            .foregroundStyle(PixelHandTheme.ink)
            .accessibilityAddTraits(.isHeader)
        if singleLine {
            base
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            base.fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The code in dot-matrix numerals on a navy plate: two groups of
    /// four, every digit at full brightness (OR-11: the check digit is
    /// typed too, and a dim one read as a bug), the same "4821 0934" the
    /// iPhone and iPad show.
    private func codePlate(_ code: PairingCode) -> some View {
        let pitch: CGFloat = 3
        let groups = PairingCodeDisplay.groups(code)
        return HStack(spacing: pitch * 6) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                MacDotText(group.text, pitch: pitch, glows: true)
            }
        }
        .foregroundStyle(PixelHandTheme.Brand.phosphor)
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .padding(.vertical, PixelHandTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .fill(PixelHandTheme.Brand.screenSurface)
        )
        .contentTransition(.identity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PairingCodeDisplay.spoken(code))
        .accessibilityIdentifier("ph.mac.pairingCode")
        .contextMenu {
            Button("Copy code") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.digits, forType: .string)
            }
        }
        .id(code.digits)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
    }

    /// The name people pick on the iPhone or iPad.
    static let macName: String = Host.current().localizedName ?? "this Mac"
}
