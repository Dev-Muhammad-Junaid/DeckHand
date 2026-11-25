# Visual QA, build 23

Gallery (private Artifact, screenshots for every checked item; mirror pictures blurred): https://claude.ai/artifact/Gmd7tNoxKcsQ9FnMKhYmqK

Captured 2026-11-25 on the Mac build host with Xcode 27.2 simulators against `/Applications/Pixel Hand.app` (build 23, `77d2e5c`), using the `PixelHandUITests` walks plus hand checks in the iPad simulator. Judged against the build 18 findings and the owner review.

**Counts:** 98 IDs checked against build 18: VQ-001…082 **51 pass · 4 fail · 27 not checked**; OR-01…16 **10 pass · 0 fail · 6 not checked**. New findings VQ-083…097: 15 (P1 1 · P2 4 · P3 10).

## How this run was limited

- **Two passes.** First pass (Mac in use): only walks that send nothing to the Mac. That pass's `test04` typed “hello” (no Return) into Chrome; nothing was submitted. Second pass (owner said the Mac was free): `test04`, `test05` and `test16` on iPad, `test04`, `test05` and `test06` on iPhone, the Mac menu-bar panel and pair window, and OR-16 by hand, all with a scratch TextEdit document in front.
- **Devices.** iPad Pro 11" (M5): all 17 walks, plus 7 at AX3. iPhone 17 Pro: 12 walks. By hand: iPad Stage Manager window at iPhone width, iPhone 17 Pro at AX3 and AX5, OR-16 on iPad. Not run: dark mode, iPad mini, iPhone Duo, widgets and Control Center (VQ-070…079).
- **Landscape.** The iPad simulator's windowing comes back on rotation even with Stage Manager turned off, so iPad landscape and the Macs sidebar stayed unchecked (VQ-092). iPhone landscape worked.
- **Another Mac on the network.** The picker also lists “AH’s Mac mini”. The walk taps the first Mac, so one `test04` run sent it a connection request (never approved); the rest used a local patch that picks the MacBook by name (VQ-096).

## Build 22 re-checks

| Item | Result | Notes |
| --- | --- | --- |
| Bug 1 · Try again during a slow first start | **pass** | test17 passed on iPad Pro 11 (light and AX3) and iPhone 17 Pro and captured “mac-listed”. Loom's new “LoomKit Store Start” suite passes. The no-iCloud iPad mini variant and the log lines weren't checked. |
| Bug 2 · AX3 Mac pill | **pass** | iPhone 17 Pro AX3: “Muhammad’s / MacBook Pro” on two lines, no mid-word cut, no hyphen. At AX5 both lines are cut mid-word (VQ-085). |
| Bug 3 · AX3 lock banner | **pass** | The Mac locked itself during the run, so this was checked without test04. iPhone AX3 and AX5: the banner sits under the header with Keyboard on its own row and breaks at words. iPad Stage Manager window at iPhone width: Keyboard stays on the message's row, no overlap. |
| Build 19 bug 2 · Deck tile on iPhone (test14) | **fail** | The mirror tile covers the deck header's Done and three key slots in edit mode (VQ-083). |
| OR-16 · Pointer control on the picture | **pass** | Checked by hand on the iPad: the toggle lights up and dragging on the picture moves the Mac pointer relative to where it was (slow 50 pt drag: 182 pt). A quick 210 pt flick moved it about 3,250 pt, off the mirrored display (VQ-095). |

## Every build 18 ID

| ID | Sev | Area | Build 18 finding | Build 23 | Notes |
| --- | --- | --- | --- | --- | --- |
| VQ-001 | P1 | Connect | The Mac refuses every simulator: | **not checked** | Paired simulators connect and Try again lists the Mac, but pairing an unpaired simulator over loopback wasn't re-run (test15 needs the Mac's code). |
| VQ-002 | P1 | Connect | When the Mac refuses for a policy reason (unpaired, remote path) the iPad says "Access Denied. | **not checked** | Needs the Mac to refuse a device. |
| VQ-003 | P1 | Pairing | The only pairing entry on iOS is the QR scanner ("Scan pairing code"); | **pass** | iPhone: Pair opens a code sheet with a dot-matrix 4 + 4 field and the keypad. |
| VQ-004 | P2 | Onboarding | Every onboarding scene card (pages 2–5) sits on a hard-edged square of lighter navy; | **pass** | iPad: scene cards have clean rounded corners. |
| VQ-005 | P2 | Pairing | The pairing code is 7 digits shown "5973 781" (uneven groups), while onboarding shows the example "4821… | **pass** | One 4 + 4 format everywhere: the Mac's pair window shows “3523 2608”, onboarding “4821 0934”, iOS code entry “■■■■ ■■■■”. |
| VQ-006 | P2 | Connect | Picker subtitle "Your own Macs come first." doesn't tell people what to do | **pass** | “Pick the Mac to control. It needs Pixel Hand open.” |
| VQ-007 | P2 | Connect | The picker's two header buttons are unlabelled glyphs (scan, settings) that read as abstract dot patterns; | **pass** | The scan button is labelled “Pair”. |
| VQ-008 | P3 | Pairing | Scanner hint says "Menu bar › Pixel Hand › Pair a Device…" (title case) but the Mac button reads "Pair a… | **not checked** | The scanner sheet's hint wasn't opened; Pair now goes straight to code entry. |
| VQ-009 | P2 | Settings | Switches are mint (success colour) while the slider and pickers are cobalt; | **pass** | Toggles are cobalt. |
| VQ-010 | P2 | Settings | The glass "Done" button is white text on a pale lilac fill, which reads as disabled and is low contrast | **pass** | Done reads as an active cobalt button. |
| VQ-011 | P2 | Settings | Section headers use two styles: | **pass** | One header style with glyph: LIVE MIRROR, CLIPBOARD, PRIVACY… |
| VQ-012 | P2 | Settings | With no Mac paired, Remote access and Paired Macs show two identical "No paired Macs" empty-state cards… | **not checked** | The Mac is paired, so the empty state can't show. |
| VQ-013 | P2 | Settings | About footer ships developer copy: | **pass** | About has only “Show the welcome tour again”. |
| VQ-014 | P2 | Settings | Subscription row shows PRO twice (pill badge on the left and dot-matrix PRO on the right) | **pass** | One PRO mark on the subscription row. |
| VQ-015 | P3 | Settings | Mixed straight and curly apostrophes ("device's", "Mac's" next to "Mac’s sound"); | **pass** | “Restore purchases” in Settings. The paywall footer still says “Restore Purchases” (VQ-090). |
| VQ-016 | P3 | Settings | Settings on iPad is a small centred form sheet (≈ 480 × 650 pt) with long footers; | **pass** | Settings is a large page sheet on iPad. |
| VQ-017 | P3 | Settings | The next section's header ghosts through under the inline title bar while scrolling ("Pointer and… | **pass** | No section header showing through the top bar in the captures. |
| VQ-018 | P3 | Onboarding | Page 3 scene says "LIVE / 60 FPS" but the mirror's settings top out at 30 fps | **pass** | “LIVE · 30 FPS”. |
| VQ-019 | P3 | Onboarding | Portrait body copy is centred across 3 lines; | **pass** | Body text and bullets are leading-aligned in portrait. |
| VQ-020 | P3 | Connect | The first tap on the picker's Settings button right after closing the scanner sheet is dropped | **not checked** | Tap timing after closing the scanner wasn't exercised. |
| VQ-021 | P2 | Mac app | Mac panel: | **pass** | Mac panel: the crash-reports checkbox is cobalt and nothing has a focus ring when the panel opens. The pair window's New code still does (VQ-094). |
| VQ-022 | P3 | Mac app | Pairing window: | **pass** | “Scan with your iPhone or iPad” on one line; “Works once, for 4:53”. |
| VQ-023 | P2 | Mac app | While a device's request is being refused or pending the panel header still says "Ready for a device" and… | **not checked** | Needs a device that's refused or pending. |
| VQ-024 | P1 | Deck | Deck column header is crushed: | **pass** | iPad portrait deck header: “Home · 01/02”, pin and Edit, nothing wraps. |
| VQ-025 | P1 | Paywall | The deck column's Pro upsell card is stacked over the "No keys yet" empty state while waiting, so both… | **pass** | Free plan: no upsell card; one state at a time. |
| VQ-026 | P2 | Paywall | Pro lock badges float: | **pass** | Lock badges sit on the gated control (Show screen, Show decks, App chips). |
| VQ-027 | P2 | Connect | When the Mac app quits mid-session the iPad shows a modal "Disconnected — the connection was closed. | **not checked** | Would mean quitting the Mac app. |
| VQ-028 | P2 | Connect | The "Reconnecting…" toast shows a lit mint dot while disconnected (spec: | **not checked** | Would mean quitting the Mac app. |
| VQ-029 | P2 | Pairing | Code entry: | **pass** | iOS: one 4 + 4 format in onboarding and code entry, dot-matrix field, “Type the code showing on <Mac>”. |
| VQ-030 | P2 | Pairing | On iPhone the number pad covers half of the "Pair" button in the code sheet; | **pass** | iPhone: “Connect and pair” sits above the keypad. A second floating copy covers the footer (VQ-086). |
| VQ-031 | P3 | Pairing | The code field isn't focused when the sheet opens; | **pass** | The keypad is up as soon as the sheet opens. |
| VQ-032 | P2 | Shell | Header truncates the Mac name in the middle ("Mu…k Pro") to fit four header buttons | **pass** | iPhone header: “Muhammad’s MacBoo…” truncates at the tail. |
| VQ-033 | P2 | Keyboard | With the keyboard up the trackpad shrinks to a ~110 pt strip (spec: | **not checked** | iPad: the pad stays usable with the keyboard up. iPhone: the walk opened on the Deck tab, so the pad wasn't on screen. |
| VQ-034 | P3 | Keyboard | Modifier/arrow row is a line of unlabelled glyphs (⌘ ⌥ ^ ⇧ ⟲ ⇥ ← ↓) that runs off the right edge with no… | **fail** | iPhone: the modifier row still runs off the right edge (“↓” cut) with no fade. iPad fits. |
| VQ-035 | P3 | Shell | More menu: | **pass** | More menu: “Disconnect”, classic layout marked “(debug)”. |
| VQ-036 | P2 | Keyboard | Typing goes to whatever app is frontmost on the Mac; | **pass** | The keyboard bar names the target (“Typing into TextEdit”) and “hello” landed in the scratch document. |
| VQ-037 | P1 | Pairing | The Mac drops a pending request after 45 s even while the person is typing the pairing code (the code… | **pass** | The code sheet has “Connect and pair”. The 45 s expiry itself wasn't re-run. |
| VQ-038 | P2 | Mirror | Mirror status strip truncates the Mac name mid-word and drops the apostrophe: | **pass** | iPad Pro: strip reads “MUHAMMAD’S · DESK 1/2 · 15 FPS”. iPad mini not run. |
| VQ-039 | P2 | Shell | The dock's last app icon is cut in half at the trailing edge with no fade or scroll cue | **not checked** | iPad mini not run. |
| VQ-040 | P2 | Mac app | Updates… looks disabled (dim text) and pressing it does nothing visible in this build (Sparkle has no key); | **pass** | The Updates button is gone from the panel. |
| VQ-041 | P3 | Mac app | Paired list shows stale "Last seen" times (iPad Pro 11 "36 minutes ago" minutes after it was connected)… | **pass** | “Last seen” is fresh (38 s, 56 s). The real iPad still shows as “iPad”, which is the name iPadOS gives apps. |
| VQ-042 | P2 | Mac app | When the panel opens, keyboard focus lands on the first "Forget…" button (thick ring); | **pass** | No initial focus; Forget is in each row's ⋯ menu, not a button. |
| VQ-043 | P3 | Mac app | Request card shows an orange iPhone glyph for an iPad; | **not checked** | Needs a pending request. |
| VQ-044 | P3 | Connect | SEARCHING uses an amber dot (amber is reserved for "needs you"); | **pass** | “Can’t find your Mac?” link; no duplicate hint. |
| VQ-045 | P1 | Shell | In landscape the leading rail crushes the Mac pill to "R…", the deck panel to "H… / Pag…", clips the "Add… | **pass** | iPhone landscape: pill keeps the first word, deck pane isn't crushed, Edit isn't clipped. The rail hint is still cut (VQ-091). |
| VQ-046 | P2 | Mirror | Choosing the Screen tab shows an empty state with a "Show screen" button instead of starting the mirror; | **pass** | The Screen tab starts the mirror. |
| VQ-047 | P2 | Deck | Add key sheet: | **pass** | Add key sheet: search pinned at the top, descriptions wrap to two lines. |
| VQ-048 | P3 | Deck | Edit mode on an empty page is a single small dashed "Add key" tile in the top-left of a blank canvas | **pass** | iPhone edit mode shows Add key plus a row of dashed ghost tiles. |
| VQ-049 | P2 | Ask | Plan step 3 shows the typed text with its Return as a broken quote across two lines ("Type "apple.com" / " ") | **pass** | “Type “apple.com” then Return” on one line. |
| VQ-050 | P3 | Ask | Ask sheet title and placeholder truncate ("Ask Muhammad’s Mac…", "Tell Muhammad’s MacBook Pro what t…") | **pass** | Placeholder “What should your Mac do?”. |
| VQ-051 | P2 | Capture | Capture preview shows the Mac screenshot as a small band in the middle of a tall black area (about a… | **pass** | The capture fills the width with the toolbar right under it. |
| VQ-052 | P2 | Capture | The header's capture button takes a full-screen shot immediately; | **not checked** | The capture menu wasn't opened. |
| VQ-053 | P2 | Settings | Play the Mac’s sound and "Follow the cursor between displays" appear twice (per-Mac section and Live mirror); | **pass** | No duplicated settings; short footers. |
| VQ-054 | P2 | Settings | No Diagnostics section in iOS Settings (couldn't find a way to see connection diagnostics or export logs); | **pass** | Settings › Diagnostics with link, round trip, protocol and Export logs. |
| VQ-055 | P1 | Paywall | Tapping "Try Pixel Hand Pro free for 2 weeks" in Settings closed Settings and showed no paywall in the… | **pass** | The paywall opens from Settings and shows “Couldn’t reach the App Store… Try again”. |
| VQ-056 | P2 | Shell | Context strip opens with three unlabelled square buttons (← ▶ →) with grey dots under them; | **pass** | “Previous / Play/Pause / Next” with labels. |
| VQ-057 | P3 | Multiple Macs | My Macs sheet: | **pass** | Mac card plus an “Add another Mac” ghost card; Disconnect is a plain row. |
| VQ-058 | P2 | Connect | After onboarding the paired Mac shows "Paired / Nearby" but the app waits for a tap instead of… | **fail** | After onboarding, and after a plain relaunch, the picker shows “Paired · Nearby” and waits for a tap. |
| VQ-059 | P1 | Mirror | With the mirror on, the area under it switches to the classic TrackpadView: | **pass** | iPhone Screen tab: the new dot pad (Click / Right-click) under the mirror, no classic trackpad, no slider. |
| VQ-060 | P2 | Mirror | Picture in Picture has no button in the mirror toolbar unless Settings › "Keep watching in Picture in… | **fail** | iPad: the PiP button is in the mirror toolbar. iPhone: it isn't (the walk recorded ph.mirror.pictureInPicture as missing). |
| VQ-061 | P3 | Mirror | The mirror toolbar sits on top of the picture's bottom edge and never fades, hiding the Mac's Dock in the… | **fail** | iPad: the toolbar hides and a tap brings it back. iPhone: it's still up at 4 s. |
| VQ-062 | P3 | Mirror | While the mirror is connecting the status strip shows a lit green dot with "0 FPS" | **not checked** | The mirror showed frames at once; the connecting state wasn't caught. |
| VQ-063 | P3 | Shell | The context strip's empty hint "Bring an app to the front on the Mac" appears whenever Pixel Hand's own… | **not checked** | TextEdit was in front for the whole run. |
| VQ-064 | P1 | Onboarding | At AX3 the onboarding body text runs under the page dots and buttons and is cut mid-line ("…with the… | **not checked** | iPhone AX3 onboarding wasn't run. iPad AX3 onboarding reads fine. |
| VQ-065 | P1 | Shell | At AX3 the Mac pill collapses to "…" (no Mac name at all) while the header glyph buttons stay tiny; | **pass** | iPhone AX3: pill reads “Muhammad’s / MacBook Pro” on two lines; one menu button. AX5 still cuts mid-word (VQ-085). |
| VQ-066 | P1 | Paywall | Free-plan upsell card in the deck: | **not checked** | iPhone AX3 free plan wasn't run. |
| VQ-067 | P2 | Duo | Unfolded, onboarding uses one centred column, so the title, art and body run across the crease; | **not checked** | Duo not run. |
| VQ-068 | P3 | Connect | The "Mac is locked" state works (amber banner under the header, "Locked" on the sidebar card, the mirror… | **pass** | “<Mac> is locked. Type the password to unlock.” with Keyboard. |
| VQ-069 | P2 | Connect | In four consecutive launches the paired Mac didn't appear in the picker within 45 s ("Looking for your… | **pass** | The paired Mac appeared at once on every launch in this run. |
| VQ-070 | P2 | Widgets | The small Deck widget's status strip cuts the Mac name mid-word to six letters ("MUHAMM"); | **not checked** | Widgets not re-added in this run. |
| VQ-071 | P2 | Widgets | The dot-matrix font has no apostrophe, so "Muhammad's MacBook Pro" reads "MUHAMMAD S MACBOOK PRO" on every… | **not checked** | Widgets not re-added. The in-app mirror strip does draw the apostrophe. |
| VQ-072 | P3 | Widgets | The medium widget's strip ends in "/ MAC", which says nothing; | **not checked** | Widgets not re-added in this run. |
| VQ-073 | P3 | Widgets | Small Deck widget: | **not checked** | Widgets not re-added in this run. |
| VQ-074 | P1 | Lock Screen | The Lock Screen "Mac Keys" rectangular widget overflows: | **not checked** | Lock Screen widgets not re-added. |
| VQ-075 | P3 | Lock Screen | The circular Mac Keys widget is a bare glyph with no disc behind it, so next to system circular widgets it… | **not checked** | Lock Screen widgets not re-added. |
| VQ-076 | P2 | Control Center | The three controls use stock SF Symbols (square.grid.3x2, the system Mission Control symbol, hand.draw)… | **not checked** | Control Center not re-checked. |
| VQ-077 | P2 | Control Center | The controls pick up system tints: | **not checked** | Control Center not re-checked. |
| VQ-078 | P2 | Control Center | With an empty deck, Deck Key's Choose sheet says only "No options available."; | **not checked** | Control Center not re-checked. |
| VQ-079 | P3 | Control Center | The control is "Open Trackpad" in the gallery but "Trackpad" on its label, and on iPad it opens the full… | **not checked** | Control Center not re-checked. |
| VQ-080 | P2 | Stage Manager | In a Stage Manager window the window controls (red, yellow, green) sit on top of the Mac pill's icon, at… | **pass** | Stage Manager: window controls sit clear of the Mac pill. |
| VQ-081 | P2 | Stage Manager | At iPhone width (about 375 pt) the Mac pill truncates the name in the middle to "M…ro" and the app to… | **pass** | At iPhone width the header folds to two buttons and the name truncates at the end. |
| VQ-082 | P3 | Deck | The deck header shows the page twice: | **pass** | Only the dot-matrix 01/02. |
| OR-01 | OR | Owner review | Tab bar selection dot | **pass** | iPhone tab bar: fill only, no dot. |
| OR-02 | OR | Owner review | Dots under chips | **pass** | No dot row under chips. |
| OR-03 | OR | Owner review | Pro upsell cards | **pass** | Free plan on iPad and iPhone: lock badges on controls, no upsell cards; paywall opens from Settings. |
| OR-04 | OR | Owner review | Macs sidebar too wide | **not checked** | The sidebar needs landscape, and the iPad didn't rotate with windowing on (VQ-092). |
| OR-05 | OR | Owner review | Sidebar button jumps | **not checked** | Same as OR-04. |
| OR-06 | OR | Owner review | Right column: collapse, Deck | Ask | **pass** | Deck | Ask switch, Ask runs in the column, collapse widens the pad. |
| OR-07 | OR | Owner review | Stage Manager header | **pass** | Stage Manager header inset and fold-in, see VQ-080 and VQ-081. |
| OR-08 | OR | Owner review | Mac panel: one Devices list | **pass** | One Devices list with state per row, ⋯ menu per row, one Pair a device button, no Paired section. |
| OR-09 | OR | Owner review | Mac panel animation | **not checked** | Opening animation not judged from stills. |
| OR-10 | OR | Owner review | Pair window QR centring | **pass** | The hand tile is centred on the QR code. |
| OR-11 | OR | Owner review | Faded check digit | **pass** | All 8 digits at full brightness. |
| OR-12 | OR | Owner review | Ellipses on buttons | **pass** | Mac: Pair a device, New code, Cancel, Quit; iOS: Pair, Disconnect. No ellipses seen. |
| OR-13 | OR | Owner review | Transfers tab | **not checked** | Needs several transfers in flight. |
| OR-14 | OR | Owner review | Widgets and Control Center (VQ-070–079) | **not checked** | Widgets and Control Center not re-checked. |
| OR-15 | OR | Owner review | Widget dot glyphs | **not checked** | Widgets not re-checked. |
| OR-16 | OR | Owner review | Pointer control on the picture | **pass** | iPad, by hand: the toggle lights up and a slow 50 pt drag moves the Mac pointer 182 pt. A quick flick throws it off the mirrored display (VQ-095). |

## New findings

`ID · severity · category · area · device · what's wrong · suggested fix · gallery image`

- VQ-083 · P1 · Behaviour · Deck · iPhone 17 Pro · In deck edit mode the floating mirror tile sits over the header's trailing side: Done is hidden under it (the walk recorded it as not hittable) and it covers three of the dashed key slots. Build 19 bug 2 (deck tile on iPhone) is still open. · Keep the tile below the deck header, or move it aside while editing; never over header controls. · iphone-deck-edit-tile
- VQ-084 · P2 · Accessibility · Picker · iPhone 17 Pro AX3, iPad Pro 11 AX3 · At AX3 the picker truncates the subtitle (“Pick the Mac to contr…”), cuts the Mac name in the middle (“Muh…ok Pro”) and cuts the status (“Paired · Near…”). · Let the Mac card grow and break the name over two lines, as the header pill does; tail truncation only. · iphone-ax3-picker
- VQ-085 · P2 · Accessibility · Shell · iPhone 17 Pro AX5 · At AX5 the Mac pill cuts both lines mid-word (“Muhamma… / MacBook…”). The build 22 fix says the first word shrinks to 70 % before it truncates; that doesn't show here. · Apply the shrink before truncation at AX5, or fall back to the first word only. · iphone-ax5-pill
- VQ-086 · P2 · Layout · Pairing · iPhone 17 Pro · The code sheet shows a second, floating “Connect and pair” capsule at the keypad's top edge that covers the footer (“Not connected to Muhammad’s… Hand connects again and…”). The title truncates to “Pair with Muhammad’s MacBook…”. · Keep one Connect and pair button; let the footer wrap above the keypad; title “Pair” with the Mac name below. · iphone-pair-sheet
- VQ-087 · P3 · Accessibility · Shell · iPad Pro 11 AX3 · The right column's switch reads “De… | Ask” and the Ask placeholder “What shou…” at AX3. · Glyph-only segments with a Large Content Viewer at the Huge band, or stack the switch. · ipad-ax3-column
- VQ-088 · P3 · Layout · Shell · iPad Pro 11 portrait · The chip row ends mid-label at the trailing edge (“Focus L…”, “Red…”) with no fade or scroll cue. · Fade the trailing edge, as the dock should (VQ-039). · ipad-keyboard
- VQ-089 · P3 · Accessibility · Settings · iPad Pro 11 AX3 · Segmented controls (frame rate, send rate, quality, theme) stay at the small default size at AX3 while the rows around them grow. · Use a menu picker at accessibility sizes, or let the segments scale. · ipad-ax3-settings
- VQ-090 · P3 · Wording · Paywall · iPad Pro 11, iPhone 17 Pro · The paywall footer says “Restore Purchases”; Settings says “Restore purchases”. · Sentence case in both. · ipad-paywall
- VQ-091 · P3 · Layout · Shell · iPhone 17 Pro landscape · The rail's empty-state hint is cut mid-word at the rail's edge (“Bring an app to the front c…”). · Wrap the hint or shorten it to “Bring an app to the front”. · iphone-landscape
- VQ-092 · P3 · Test tooling · UI tests · iPad Pro 11 (Stage Manager on) · test02 and test11 capture portrait on the iPad because the simulator has windowing on, so iPad landscape (and the Macs sidebar, OR-04/05) isn't checked by the walks. · Turn windowing off for QA runs, or have the walk make the window full-screen before rotating. · —
- VQ-093 · P3 · Test tooling · Mirror · iPad Pro 11 · With pointer control turned on, test16 can't find ph.mirror.pointerSurface, so OR-16's surface isn't verified by the walk. · Add the identifier to the pointer surface (or update the walk to the identifier it uses). · ipad-picture-pointer
- VQ-094 · P3 · Visual identity · Mac app · Mac · The pair window opens with a thick pink focus ring (the system accent) on New code. · Give no button initial focus, or tint the focus ring cobalt. · mac-pair-window
- VQ-095 · P2 · Behaviour · Mirror · iPad Pro 11 · With pointer control on, a quick ~210 pt flick on the picture moved the Mac pointer about 3,250 pt, off the mirrored display and onto another screen, where the picture can't show it. A slow 50 pt drag moved it 182 pt, which feels right. · Keep the pointer on the mirrored display while pointer control is on, or cap the acceleration for flicks. · ipad-or16
- VQ-096 · P3 · Test tooling · UI tests · Any simulator · connect() taps the first Mac in the picker. With another Mac on the network (“AH’s Mac mini”) the walk sent a connection request to that Mac instead of the build host. · Let the walk pick the Mac by name (this run used a local, uncommitted PH_QA_MAC patch). · —
- VQ-097 · P3 · Behaviour · Mac app · Mac · “Last seen 38 seconds ago” doesn't tick while the panel stays open. · Use a relative date that updates (TimelineView), or show the time. · mac-panel
