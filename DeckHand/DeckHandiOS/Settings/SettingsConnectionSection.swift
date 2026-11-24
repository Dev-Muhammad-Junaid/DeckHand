//
//  SettingsConnectionSection.swift
//  DeckHandiOS
//
//  Settings › Connection: the live session's link (S13) and same-iCloud
//  recognition; Settings › Remote Access (S15): the addresses used to reach
//  each paired Mac over a VPN, with a test button. Split out of
//  SettingsView.swift (PH-010). Network lane.
//

import SwiftUI

struct SettingsConnectionSection: View {
    @EnvironmentObject private var settings: DeckHandSettings
    private let linkStatus = RemoteLinkStatus.shared
    private let pairing = PairedMacsStore.shared

    var body: some View {
        Section {
            if let link = linkStatus.current {
                LabeledContent {
                    Label(link.displayName, systemImage: link.systemImage)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(link == .wired ? AnyShapeStyle(PixelHandTheme.accent) : AnyShapeStyle(.secondary))
                } label: {
                    Text("Link")
                }
                .accessibilityElement(children: .combine)
            }
            CloudRecognitionRow()
        } header: {
            Text("Connection")
        } footer: {
            Text(Self.footer(link: linkStatus.current, isAway: linkStatus.isAway))
        }

        Section {
            if pairing.macs.isEmpty {
                // UX-018: the glyph empty state on navy.
                PixelSurface(cornerRadius: PixelHandTheme.Radius.card) {
                    PHEmptyState(glyph: PixelGlyphs.mac, title: "No paired Macs", message: "Pair with a Mac first, then set up its addresses here.")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                ForEach(pairing.macs) { mac in
                    NavigationLink {
                        RemoteAccessMacView(mac: mac)
                    } label: {
                        RemoteAccessMacRow(mac: mac)
                    }
                }
            }
        } header: {
            Text("Remote Access")
        } footer: {
            Text("Reach a paired Mac over Tailscale or another VPN when it isn’t on the same Wi-Fi. A Mac on the VPN tells this device its address while you’re connected at home; you can also add a host name or IP address yourself. Only paired Macs can be reached this way.")
        }
    }

    static func footer(link: LinkKind?, isAway: Bool = false) -> String {
        switch link {
        case .wired:
            return "Connected by USB cable: no Wi-Fi in the way, and no keep-alive traffic needed.\n\n" + CloudRecognitionStatus.footer
        case .tunnel:
            return "Connected over a VPN to a paired Mac. The mirror uses fewer frames and a smaller picture so it stays responsive.\n\n" + CloudRecognitionStatus.footer
        default:
            if isAway {
                return "The link is slow, so the mirror uses fewer frames and a smaller picture.\n\n" + CloudRecognitionStatus.footer
            }
            return CloudRecognitionStatus.footer
        }
    }
}

/// One paired Mac in Settings › Remote Access.
private struct RemoteAccessMacRow: View {
    let mac: PairedDevice
    private let hostsStore = RemoteHostsStore.shared

    var body: some View {
        let count = hostsStore.hosts(for: mac.ref).count
        HStack(spacing: 12) {
            Image(systemName: mac.kind.systemImage)
                .foregroundStyle(PixelHandTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name)
                Text(count == 0 ? "No saved addresses" : count == 1 ? "1 address" : "\(count) addresses")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A paired Mac's saved VPN addresses: add, remove, test.
struct RemoteAccessMacView: View {
    let mac: PairedDevice
    private let hostsStore = RemoteHostsStore.shared
    @State private var draft = ""
    @State private var draftError: String?
    @State private var results: [String: RemoteAccessPolicy.ProbeVerdict] = [:]
    @State private var isTesting = false

    private var hosts: [SavedRemoteHost] { hostsStore.hosts(for: mac.ref) }

    var body: some View {
        Form {
            Section {
                if hosts.isEmpty {
                    Text("No saved addresses")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hosts) { saved in
                        hostRow(saved)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { hosts[$0].host }
                        for host in doomed { hostsStore.remove(host, for: mac.ref) }
                    }
                }
            } header: {
                Text("Addresses")
            } footer: {
                Text("Addresses marked “From the Mac” are updated each time you connect at home.")
            }

            Section {
                TextField("100.x.y.z or name.tailnet.ts.net", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button("Add Address", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Add an Address")
            } footer: {
                Text(draftError ?? "A Tailscale IP or MagicDNS name, or the Mac’s address on another VPN. Host only: no http://, port or path.")
                    .foregroundStyle(draftError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }

            Section {
                Button {
                    test()
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting { DotWave(pitch: 3, label: "Testing") }
                    }
                }
                .disabled(hosts.isEmpty || isTesting)
            } footer: {
                Text("Checks whether \(mac.name) answers at each address. Turn the VPN on for both devices and keep Pixel Hand open on the Mac.")
            }
        }
        .navigationTitle(mac.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hostRow(_ saved: SavedRemoteHost) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(saved.host.value)
                .font(.body.monospaced())
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text(saved.source == .mac ? "From the Mac" : "Added by you")
                if let verdict = results[saved.host.value] {
                    Text("·")
                    Label(label(for: verdict), systemImage: icon(for: verdict))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(verdict == .reachable ? AnyShapeStyle(PixelHandTheme.accent) : AnyShapeStyle(.orange))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let verdict = results[saved.host.value], verdict != .reachable {
                Text(verdict.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(for verdict: RemoteAccessPolicy.ProbeVerdict) -> String {
        switch verdict {
        case .reachable: "Reachable"
        case .differentMac: "Another Mac"
        case .noAnswer: "No answer"
        }
    }

    private func icon(for verdict: RemoteAccessPolicy.ProbeVerdict) -> String {
        switch verdict {
        case .reachable: "checkmark.circle.fill"
        case .differentMac: "exclamationmark.triangle.fill"
        case .noAnswer: "xmark.circle"
        }
    }

    private func add() {
        switch hostsStore.add(draft, for: mac.ref) {
        case .success:
            draft = ""
            draftError = nil
        case let .failure(error):
            switch error {
            case let .invalid(rejection): draftError = rejection.message
            case .duplicate: draftError = "That address is already saved."
            case .full: draftError = "Remove an address first (up to \(RemoteHostBook.maxUserHostsPerMac))."
            case .notPaired: draftError = "This Mac is no longer paired."
            }
        }
    }

    private func test() {
        isTesting = true
        results = [:]
        let targets = hosts.map(\.host)
        let ref = mac.ref
        Task {
            let found = await RemoteHostTester.test(targets, for: ref)
            results = Dictionary(found.map { ($0.host.value, $0.verdict) }, uniquingKeysWith: { a, _ in a })
            isTesting = false
        }
    }
}
