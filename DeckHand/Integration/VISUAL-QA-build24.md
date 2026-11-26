# Visual QA, build 24

Gallery (private Artifact; mirror pictures blurred where they show the Mac's screen): https://claude.ai/artifact/GqAPQEFb6QVVixc8KkaufT

Captured 2026-11-26 on the Mac build host with Xcode 27.2 simulators against `/Applications/Pixel Hand.app` (build 24, `7b205ca`), using the `PixelHandUITests` walks (with `PH_QA_MAC_NAME` and, on iPad, `PH_QA_FULLSCREEN=1`) and hand checks. Statuses carry over from `VISUAL-QA-build23.md` and are updated where this pass checked them.

**Counts:** VQ-001…097 **74 pass · 1 fail · 22 not checked**; OR-01…16 **12 pass · 0 fail · 4 not checked**. The qa23 fix lane's 20 IDs: **20 pass · 0 fail · 0 not checked**. New findings VQ-098…103: 6 (P1 0 · P2 3 · P3 3).

## How this pass ran

- **The owner freed the Mac** and a scratch TextEdit document was in front. `test04` typed “hello” (no Return) into it from the iPad and the iPhone. Partway through the iPhone run the Mac's front app changed to Universal Control and then Chrome; only `test04` types, and it ran while TextEdit was in front.
- **Walks:** iPad Pro 11" light, all 17 (full screen, real landscape); iPhone 17 Pro light, all 17; AX3 on iPhone (5) and iPad (3); dark mode on iPad (5); iPad mini (Mac-free set, see VQ-103). All passed.
- **By hand:** OR-16 flick and clamp on the iPad (pointer read on the Mac), the iPhone pairing sheet, the iPhone at AX5, the Mac panel and pair window, the Home Screen widget gallery.
- **Not run:** Lock Screen and Control Center (VQ-074…079), transfers (OR-13; the real iPad wasn't reachable, CoreDevice 4016), the sidebar's hidden state (OR-05), Duo.

## Re-checks this build asked for

| Item | Result | Notes |
| --- | --- | --- |
| Fix lane qa23 · 19 IDs | **pass** | All 17 fixed or tooling items pass (VQ-058, 060, 061, 083…097), and the two partial ones (VQ-034, VQ-088) pass too. |
| iPad landscape and Macs sidebar | **pass** | Real landscape with PH_QA_FULLSCREEN=1: two-column onboarding and the shell with a compact sidebar (OR-04). OR-05's hidden state wasn't captured. |
| Widgets | **pass** | Home Screen Deck widgets pass VQ-070…073. Lock Screen and Control Center not checked. |
| Dark mode | **pass** | iPad onboarding, picker, Settings, free plan, paywall and right column: consistent, readable, cobalt controls. |
| Transfers (OR-13) | **not checked** | Not run: the real iPad wasn't reachable (CoreDevice 4016), and transfers need real files both ways. |
| iPad mini | **not checked** | test01, test03, test11, test13 passed. Onboarding, the picker and the pair sheet render; the connect walks waited for an Allow on the Mac and timed out because this simulator was never paired (VQ-103), so the shell (VQ-038, VQ-039) wasn’t reached. |

## Every ID

| ID | Sev | Area | Finding | Build 24 | Notes |
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
| VQ-033 | P2 | Keyboard | With the keyboard up the trackpad shrinks to a ~110 pt strip (spec: | **not checked** | Not re-checked: on iPhone the keyboard walk opened over the mirror, so the pad wasn't on screen. |
| VQ-034 | P3 | Keyboard | Modifier/arrow row is a line of unlabelled glyphs (⌘ ⌥ ^ ⇧ ⟲ ⇥ ← ↓) that runs off the right edge with no… | **pass** | iPhone: the modifier row now fades out over the last key (one key wide). |
| VQ-035 | P3 | Shell | More menu: | **pass** | More menu: “Disconnect”, classic layout marked “(debug)”. |
| VQ-036 | P2 | Keyboard | Typing goes to whatever app is frontmost on the Mac; | **pass** | The keyboard bar names the target (“Typing into TextEdit”) and “hello” landed in the scratch document. |
| VQ-037 | P1 | Pairing | The Mac drops a pending request after 45 s even while the person is typing the pairing code (the code… | **pass** | The code sheet has “Connect and pair”. The 45 s expiry itself wasn't re-run. |
| VQ-038 | P2 | Mirror | Mirror status strip truncates the Mac name mid-word and drops the apostrophe: | **not checked** | iPad mini: see VQ-103; the run couldn't connect. |
| VQ-039 | P2 | Shell | The dock's last app icon is cut in half at the trailing edge with no fade or scroll cue | **not checked** | iPad mini: see VQ-103. |
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
| VQ-058 | P2 | Connect | After onboarding the paired Mac shows "Paired / Nearby" but the app waits for a tap instead of… | **pass** | Reconnects at launch: the picker walk is already in the shell 1 s after launch on iPad and iPhone. After a cold simulator boot the iPhone took 7–15 s (VQ-101). |
| VQ-059 | P1 | Mirror | With the mirror on, the area under it switches to the classic TrackpadView: | **pass** | iPhone Screen tab: the new dot pad (Click / Right-click) under the mirror, no classic trackpad, no slider. |
| VQ-060 | P2 | Mirror | Picture in Picture has no button in the mirror toolbar unless Settings › "Keep watching in Picture in… | **pass** | iPhone: the PiP button is in the mirror toolbar; on the simulator, which can't do PiP, it explains that in an alert. |
| VQ-061 | P3 | Mirror | The mirror toolbar sits on top of the picture's bottom edge and never fades, hiding the Mac's Dock in the… | **pass** | iPhone: still up at 4 s, gone by the next capture; it now hides. |
| VQ-062 | P3 | Mirror | While the mirror is connecting the status strip shows a lit green dot with "0 FPS" | **not checked** | The mirror showed frames at once; the connecting state wasn't caught. |
| VQ-063 | P3 | Shell | The context strip's empty hint "Bring an app to the front on the Mac" appears whenever Pixel Hand's own… | **not checked** | TextEdit was in front for the whole run. |
| VQ-064 | P1 | Onboarding | At AX3 the onboarding body text runs under the page dots and buttons and is cut mid-line ("…with the… | **pass** | iPhone AX3: onboarding text and buttons scroll together; Continue and Back sit after the text. |
| VQ-065 | P1 | Shell | At AX3 the Mac pill collapses to "…" (no Mac name at all) while the header glyph buttons stay tiny; | **pass** | iPhone AX3: pill reads “Muhammad’s / MacBook Pro” on two lines; one menu button. AX5 still cuts mid-word (VQ-085). |
| VQ-066 | P1 | Paywall | Free-plan upsell card in the deck: | **fail** | iPhone AX3 free plan: the Screen card's Show screen button is still cut by the card's bottom edge. |
| VQ-067 | P2 | Duo | Unfolded, onboarding uses one centred column, so the title, art and body run across the crease; | **not checked** | Duo not run. |
| VQ-068 | P3 | Connect | The "Mac is locked" state works (amber banner under the header, "Locked" on the sidebar card, the mirror… | **pass** | “<Mac> is locked. Type the password to unlock.” with Keyboard. |
| VQ-069 | P2 | Connect | In four consecutive launches the paired Mac didn't appear in the picker within 45 s ("Looking for your… | **pass** | The paired Mac appeared at once on every launch in this run. |
| VQ-070 | P2 | Widgets | The small Deck widget's status strip cuts the Mac name mid-word to six letters ("MUHAMM"); | **pass** | Small Deck widget: “MUHAMMAD’S”, a whole word, not prefix(6). |
| VQ-071 | P2 | Widgets | The dot-matrix font has no apostrophe, so "Muhammad's MacBook Pro" reads "MUHAMMAD S MACBOOK PRO" on every… | **pass** | The dot font draws the apostrophe: “MUHAMMAD’S MACBOOK PRO”. |
| VQ-072 | P3 | Widgets | The medium widget's strip ends in "/ MAC", which says nothing; | **pass** | Medium widget strip: “MUHAMMAD’S MACBOOK PRO · OFFLINE”, a state instead of “MAC”. |
| VQ-073 | P3 | Widgets | Small Deck widget: | **pass** | Small widget labels: Mission, Desktop, Play, Lock, one size. |
| VQ-074 | P1 | Lock Screen | The Lock Screen "Mac Keys" rectangular widget overflows: | **not checked** | Lock Screen widgets not added. |
| VQ-075 | P3 | Lock Screen | The circular Mac Keys widget is a bare glyph with no disc behind it, so next to system circular widgets it… | **not checked** | Lock Screen widgets not added. |
| VQ-076 | P2 | Control Center | The three controls use stock SF Symbols (square.grid.3x2, the system Mission Control symbol, hand.draw)… | **not checked** | Control Center not checked. |
| VQ-077 | P2 | Control Center | The controls pick up system tints: | **not checked** | Control Center not checked. |
| VQ-078 | P2 | Control Center | With an empty deck, Deck Key's Choose sheet says only "No options available."; | **not checked** | Control Center not checked. |
| VQ-079 | P3 | Control Center | The control is "Open Trackpad" in the gallery but "Trackpad" on its label, and on iPad it opens the full… | **not checked** | Control Center not checked. |
| VQ-080 | P2 | Stage Manager | In a Stage Manager window the window controls (red, yellow, green) sit on top of the Mac pill's icon, at… | **pass** | Stage Manager: window controls sit clear of the Mac pill. |
| VQ-081 | P2 | Stage Manager | At iPhone width (about 375 pt) the Mac pill truncates the name in the middle to "M…ro" and the app to… | **pass** | At iPhone width the header folds to two buttons and the name truncates at the end. |
| VQ-082 | P3 | Deck | The deck header shows the page twice: | **pass** | Only the dot-matrix 01/02. |
| VQ-083 | P1 | Deck | In deck edit mode the floating mirror tile sits over the header's trailing side: Done is hidden under it (the  | **pass** | iPhone edit mode: the mirror tile steps aside; Done and the ghost key row are clear. |
| VQ-084 | P2 | Picker | At AX3 the picker truncates the subtitle (“Pick the Mac to contr…”), cuts the Mac name in the middle (“Muh…ok  | **pass** | AX3 and AX5 picker: subtitle wraps, Mac names break at whole words (“AH’s Mac / mini”). |
| VQ-085 | P2 | Shell | At AX5 the Mac pill cuts both lines mid-word (“Muhamma… / MacBook…”) | **pass** | AX5: the pill reads “Muhammad’s / MacBook Pro” in full. |
| VQ-086 | P2 | Pairing | The code sheet shows a second, floating “Connect and pair” capsule at the keypad's top edge that covers the fo | **pass** | One Connect and pair button, no floating copy; title “Pair”. The footer still runs under the keypad (VQ-100). |
| VQ-087 | P3 | Shell | The right column's switch reads “De… | Ask” and the Ask placeholder “What shou…” at AX3. | **pass** | iPad AX3: Deck | Ask shows glyphs; placeholder “Ask your Mac”. |
| VQ-088 | P3 | Shell | The chip row ends mid-label at the trailing edge (“Focus L…”, “Red…”) with no fade or scroll cue. | **pass** | iPad chip row fades out over “Delete” at the trailing edge. |
| VQ-089 | P3 | Settings | Segmented controls (frame rate, send rate, quality, theme) stay at the small default size at AX3 while the row | **pass** | AX3: segmented pickers become menus (“120 Hz ⌃”, “Full ⌃”, “Standard ⌃”, “System ⌃”). |
| VQ-090 | P3 | Paywall | The paywall footer says “Restore Purchases”; Settings says “Restore purchases”. | **pass** | Paywall footer: “Restore purchases”. |
| VQ-091 | P3 | Shell | The rail's empty-state hint is cut mid-word at the rail's edge (“Bring an app to the front c…”). | **pass** | iPhone landscape rail: “Bring an app to the front” fits. |
| VQ-092 | P3 | UI tests | test02 and test11 capture portrait on the iPad because the simulator has windowing on, so iPad landscape (and  | **pass** | With PH_QA_FULLSCREEN=1 the iPad walks run real landscape (onboarding and the shell with the sidebar). |
| VQ-093 | P3 | Mirror | With pointer control turned on, test16 can't find ph.mirror.pointerSurface, so OR-16's surface isn't verified  | **pass** | test16 finds the pointer surface and captures pointer-control-moved and -zoomed. |
| VQ-094 | P3 | Mac app | The pair window opens with a thick pink focus ring (the system accent) on New code. | **pass** | The pair window opens with no focus ring. |
| VQ-095 | P2 | Mirror | With pointer control on, a quick ~210 pt flick on the picture moved the Mac pointer about 3,250 pt, off the mi | **pass** | By hand: the build 23 flick now moves the pointer about 630 pt (was ~3,250), and a bigger flick stops at the display edge (x = 1511). |
| VQ-096 | P3 | UI tests | connect() taps the first Mac in the picker | **pass** | PH_QA_MAC_NAME: every walk connected to the MacBook; none tapped AH’s Mac mini. |
| VQ-097 | P3 | Mac app | “Last seen 38 seconds ago” doesn't tick while the panel stays open. | **pass** | Panel: “last seen 2 min ago”, “3 min ago”, “yesterday”. |
| OR-01 | OR | Owner review | Tab bar selection dot | **pass** | iPhone tab bar: fill only, no dot. |
| OR-02 | OR | Owner review | Dots under chips | **pass** | No dot row under chips. |
| OR-03 | OR | Owner review | Pro upsell cards | **pass** | Free plan on iPad and iPhone: lock badges on controls, no upsell cards; paywall opens from Settings. |
| OR-04 | OR | Owner review | Macs sidebar too wide | **pass** | iPad landscape (full screen): the Macs sidebar is compact, about 175 pt, with short Mac cards. |
| OR-05 | OR | Owner review | Sidebar button jumps | **not checked** | The sidebar's hidden state wasn't captured, so the button's position there isn't confirmed. |
| OR-06 | OR | Owner review | Right column: collapse, Deck | Ask | **pass** | Deck | Ask switch, Ask runs in the column, collapse widens the pad. |
| OR-07 | OR | Owner review | Stage Manager header | **pass** | Stage Manager header inset and fold-in, see VQ-080 and VQ-081. |
| OR-08 | OR | Owner review | Mac panel: one Devices list | **pass** | One Devices list with state per row, ⋯ menu per row, one Pair a device button, no Paired section. |
| OR-09 | OR | Owner review | Mac panel animation | **not checked** | Opening animation not judged from stills. |
| OR-10 | OR | Owner review | Pair window QR centring | **pass** | The hand tile is centred on the QR code. |
| OR-11 | OR | Owner review | Faded check digit | **pass** | All 8 digits at full brightness. |
| OR-12 | OR | Owner review | Ellipses on buttons | **pass** | Mac: Pair a device, New code, Cancel, Quit; iOS: Pair, Disconnect. No ellipses seen. |
| OR-13 | OR | Owner review | Transfers tab | **not checked** | Transfers weren't run: the real iPad wasn't reachable (CoreDevice 4016). |
| OR-14 | OR | Owner review | Widgets and Control Center (VQ-070–079) | **not checked** | Home Screen widgets pass (VQ-070…073); Lock Screen and Control Center not checked. |
| OR-15 | OR | Owner review | Widget dot glyphs | **pass** | The widgets keep their dot glyphs and add no new dot rows. |
| OR-16 | OR | Owner review | Pointer control on the picture | **pass** | iPad, by hand: the toggle lights up and a slow 50 pt drag moves the Mac pointer 182 pt. A quick flick throws it off the mirrored display (VQ-095). |

## New findings

`ID · severity · category · area · device · what's wrong · suggested fix · gallery image`

- VQ-098 · P2 · Accessibility · Deck · iPhone 17 Pro AX3, AX5 · Outside edit mode the floating mirror tile covers the deck's “No keys yet” title at AX3, and most of the empty-state card at AX5. · Apply the VQ-083 keep-out to the empty state too, or make the tile smaller at accessibility sizes. · iphone-ax5-shell
- VQ-099 · P2 · Accessibility · Sidebar · iPad Pro 11 AX3, landscape · The Macs sidebar cards cut names mid-word at AX3: “Muh / am…”, “AH’s / Ma…”, “Text…”, “Near…”. · Use the pill's whole-word layout in the sidebar cards, or switch to glyph-only cards with the Large Content Viewer at the Huge band. · ipad-ax3-landscape
- VQ-100 · P2 · Behaviour · Pairing · iPhone 17 Pro, iPad mini · The code sheet has an unlabelled Mac chooser (a lone ⌃⌄ under the title) that defaults to the first Mac in the list. On the iPad mini it read “AH’s Mac mini” under “Type the code showing on your Mac”, so a code typed from your own Mac goes to the wrong one. On iPhone the footer also runs under the keypad after its first line. · Default to the Mac the person tapped (or the only paired/nearby Mac they chose), label the chooser (“Pairing with <Mac>”), and keep the footer above the keypad. · ipad-mini-pair
- VQ-101 · P3 · Behaviour · Connect · iPhone 17 Pro · After a cold simulator boot the paired Mac took 7–15 s to reconnect, and the picker showed “Paired · Nearby” with no sign that it was connecting. · Show “Connecting to <Mac>…” with Cancel while the auto-reconnect runs. · iphone-reconnected
- VQ-102 · P3 · Layout · Picker · iPhone 17 Pro AX5 · When the picker scrolls at AX5, the subtitle slides under the Pair and Settings buttons, which have no backdrop. · Give the picker's top bar a scroll-edge background. · iphone-ax5-picker
- VQ-103 · P3 · Test tooling · UI tests · iPad mini (A17 Pro) · The iPad mini simulator isn't paired with the build Mac, so connect() waits for an Allow that never comes and shows the Mac an approval prompt. · Pair the QA simulators once (or have the walk enter the code with PH_QA_PAIRCODE_FILE) and skip connect walks on unpaired devices. · —
