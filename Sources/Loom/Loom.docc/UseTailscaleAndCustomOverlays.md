# Use Tailscale and Custom Overlays

Loom's overlay support is intentionally narrow. It does not talk to the Tailscale admin API, Headscale, or your inventory service for you. Instead it gives you two transport-level pieces:

- a small overlay probe listener published by ``LoomNode``
- a seed-driven directory built with ``LoomOverlayDirectory``

That split is deliberate. Your app owns which hosts exist and which ones are trusted. Loom owns the Loom-native probe, identity validation, and direct-session planning built on top of those hosts.

## Treat Tailscale as direct connectivity

When two devices can reach each other over Tailscale, Loom should treat that path as a direct transport, not as signaling-only remote presence.

The usual setup is:

1. publish a local overlay probe listener on each host
2. feed ``LoomOverlayDirectory`` with MagicDNS names or stable tailnet IP addresses
3. let Loom race the overlay candidate before falling back to signaling

If you are using `LoomKit`, setting `overlayDirectory` on the container configuration is enough. When the overlay configuration omits `probePort`, the container uses Loom's default overlay probe port and wires that same probe port into the underlying ``LoomNode`` automatically.

```swift
let container = try LoomContainer(
    for: LoomContainerConfiguration(
        serviceType: "_studio._tcp",
        serviceName: "Studio Mac",
        overlayDirectory: LoomOverlayDirectoryConfiguration(
            refreshInterval: .seconds(30),
            probeTimeout: .seconds(2),
            probeAttempts: 3,
            probeRetryDelay: .milliseconds(250),
            seedProvider: {
                [
                    LoomOverlaySeed(host: "studio-mac.tailnet.example"),
                    LoomOverlaySeed(host: "100.64.0.25"),
                ]
            }
        )
    )
)
```

Use multiple probe attempts when the overlay interface may still be warming up after app launch or foregrounding. A single refresh still publishes one coherent peer set; retry attempts only make transient seed misses less visible to the caller.

`LoomOverlayDirectory` also keeps the last successfully resolved peers for a short grace window after transient probe failures. Set `retainedPeerExpiration` when your app needs a shorter or longer stale-peer window.

Use `LoomKitPortConfiguration` when a LoomKit app needs a different listener port:

```swift
let container = try LoomContainer(
    for: LoomContainerConfiguration(
        serviceType: "_studio._tcp",
        serviceName: "Studio Mac",
        ports: LoomKitPortConfiguration(
            overlayProbePort: 9952
        ),
        overlayDirectory: LoomOverlayDirectoryConfiguration(
            seedProvider: {
                [LoomOverlaySeed(host: "studio-mac.tailnet.example")]
            }
        )
    )
)
```

If you are using ``Loom`` directly, set `overlayProbePort` on ``LoomNetworkConfiguration`` for the local node and construct ``LoomOverlayDirectory`` yourself for remote peer resolution.

### Dial without answering probes

A node that only connects outward, such as a client that never needs to be discovered over the overlay, doesn't need its own probe listener. Call ``LoomOverlayDirectoryConfiguration/dialOnly()`` (or set ``LoomOverlayDirectoryConfiguration/listensForProbes`` to `false`). The directory still probes remote seeds on ``LoomOverlayDirectoryConfiguration/probePort``, but a LoomKit container leaves `overlayProbePort` unset on its node, so nothing binds that port locally:

```swift
let overlayDirectory = LoomOverlayDirectoryConfiguration(
    seedProvider: {
        [LoomOverlaySeed(host: "studio-mac.tailnet.example")]
    }
).dialOnly()
```

This also avoids an "address already in use" start failure when two nodes share one network stack, for example a client running in a simulator next to a host on the same machine.

## Pin the identity you already trust

An overlay probe answers with the advertisement of whatever Loom node listens at that host. If a tailnet address is reassigned, or a seed comes from an inventory you don't fully control, that advertisement can name a different identity key than the device you meant to reach. By default a connection plan expects the advertised key, so the handshake would succeed against the wrong device.

When your app stored the peer's identity earlier, for example when the two devices first trusted each other on a local network, pin it. Every target in the plan then expects the stored identity, and the session fails with ``LoomError/authenticationFailed`` unless the peer proves exactly that key:

```swift
guard let pin = LoomPeerIdentityPin(identityKeyID: storedIdentityKeyID) else { return }
let session = try await coordinator.connect(
    hello: hello,
    overlayPeer: overlayPeer,
    pinnedPeerIdentity: pin
)
```

`LoomKit` exposes the same option as `LoomContext.connect(_:pinnedIdentity:)`. Pins also apply to nearby and signaling targets, and automatic retries keep them. Use ``LoomConnectionPlan/pinned(to:)`` to inspect a pinned plan without connecting.

## Keep signaling as a fallback, not the primary plan

Overlay-discovered peers can still advertise signaling reachability. That is the useful shape for Tailscale: use the tailnet path when it is reachable, but keep signaling available when the overlay host is stale, asleep, or currently blocked by policy.

The key design point is that ``LoomConnectionCoordinator`` plans overlay connectivity before signaling without discarding signaling fallback. Your app does not need separate policy branches just because the same peer is visible through both systems.

## Build custom seed providers from your own control plane

`LoomOverlayDirectory` only needs host hints. The seed provider can come from any source you already own:

- a Tailscale or Headscale-backed service inventory
- CloudKit records that store overlay host names
- a product control plane or bootstrap service
- a static list of lab machines or office hosts

```swift
let overlayDirectory = LoomOverlayDirectory(
    configuration: LoomOverlayDirectoryConfiguration(
        refreshInterval: .seconds(15),
        probeTimeout: .seconds(1),
        seedProvider: {
            let records = try await inventoryClient.fetchReachableHosts()
            return records.map { record in
                LoomOverlaySeed(
                    host: record.host,
                    probePort: record.overlayProbePort
                )
            }
        }
    )
)
```

Each ``LoomOverlaySeed`` contains only a host and an optional probe-port override. That keeps the boundary clean:

- your app owns naming, inventory, and access control
- Loom validates that a host actually answers with a Loom advertisement
- discovered peers still become ordinary ``LoomPeer`` values that participate in the normal connection pipeline

## Operational guidance

- Use the default probe port unless you have a concrete collision. A fixed shared port keeps deployment and firewall policy simpler.
- Keep the seed list small and intentional. The directory probes every seed on each refresh interval.
- Do not overload overlay seeds with app-specific metadata. Publish only reachability hints here and keep product schema above Loom.
- If a refresh fails briefly, the directory keeps recently resolved peers until `retainedPeerExpiration` elapses or the matching seed is removed.
