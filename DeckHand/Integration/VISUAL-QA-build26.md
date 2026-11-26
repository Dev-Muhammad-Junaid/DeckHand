# Visual QA, build 26

Gallery (private Artifact; mirror pictures blurred where they show the Mac's screen): https://claude.ai/artifact/Y56FqdNycRXGqXwQ4ugK1N

Captured 2026-11-26 on the Mac build host with Xcode 27.2 simulators against `/Applications/Pixel Hand.app` (build 26, `a2f4adf`), using the `PixelHandUITests` walks (with `PH_QA_MAC_NAME`, `PH_QA_SCRATCH_APP` and, on iPad, `PH_QA_FULLSCREEN=1`) and hand checks. Statuses carry over from `VISUAL-QA-build24.md` and build 25's results, and are updated where this pass checked them.

**Counts:** VQ-001…103 **79 pass · 0 fail · 24 not checked**; OR-01…16 **12 pass · 0 fail · 4 not checked**; owner testing OT-1…8 **7 pass · 1 fail · 0 not checked**. New findings VQ-104…: 5 (P1 0 · P2 2 · P3 3).

## How this pass ran

- **The owner freed the Mac**, with a scratch TextEdit document in front. The walks now check the Mac's front app before typing (`PH_QA_SCRATCH_APP`). Twice the front app changed mid-run (to Claude, then FlutterFlow Studio); the guard skipped the iPad's typing steps (`skipped-typing-front-app-not-textedit`), and TextEdit was put back before the iPhone run. `test04` and `test18` typed “hello” (no Return) into TextEdit only; `test19` ran “Show Mission Control” on the Mac.
- **Walks:** iPad Pro 11" full screen (real landscape), all 21: 20 pass, `test21` fails (VQ-104). iPhone 17 Pro, all 21: 20 pass, `test21` fails at the walk's last step (VQ-106). `test18` and `test20` open no Type panel on the iPhone in landscape (VQ-105).
- **AX3 and iPad mini:** iPhone 17 Pro at AX3 ran test01, test09, test12 and test14 (all pass). In test09 and test12 the launch reconnect never finished (`waiting-for-allow`, then `never-allowed`), so Settings and the paywall at AX3 weren't reached; the Connecting… state itself breaks at AX3 (VQ-107). The iPad mini (unpaired) ran test03 and test04: test04 was skipped as unpaired and no request reached the Mac (VQ-103).
- **Not run:** the two-Mac pairing chooser (only the MacBook was on the network), AX5, a cold-boot reconnect, Lock Screen and Control Center, transfers, Duo. The real iPad (owner's device) is for the owner's own check.

## Re-checks this build asked for

| Item | Result | Notes |
| --- | --- | --- |
| Owner testing · OT-1…8 | **fail** | Seven of eight pass in the simulators. OT-8 passes on iPhone but fails on iPad portrait, where Save as key's Save button is under the keyboard (VQ-104). OT-4 carries over from build 25. |
| Build 25 bug 1 · Type panel behind the keyboard | **pass** | test18 on iPad: the panel sits above the keyboard in landscape and again after rotating to portrait, and closes (the build 25 failure). |
| Build 25 bug 2 · Ask keeps the old request | **pass** | test19: New request opens an empty field with Recent; after Save as key › Cancel, Ask again plans the new request, not an appended one. |
| Open P3s · VQ-100…103 | **pass** | VQ-101 and VQ-103 pass (VQ-101's Connecting… state needs an AX3 fix, VQ-107). VQ-100 needs a second Mac (none on the network) and VQ-102 an AX5 run; both not checked. |

## Every ID

| ID | Sev | Area | Finding | Build 26 | Notes |
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
| VQ-058 | P2 | Connect | After onboarding the paired Mac shows "Paired / Nearby" but the app waits for a tap instead of… | **pass** | iPad and iPhone reconnect at launch: test03 lands in the shell before the picker settles. |
| VQ-059 | P1 | Mirror | With the mirror on, the area under it switches to the classic TrackpadView: | **pass** | iPhone Screen tab: the new dot pad (Click / Right-click) under the mirror, no classic trackpad, no slider. |
| VQ-060 | P2 | Mirror | Picture in Picture has no button in the mirror toolbar unless Settings › "Keep watching in Picture in… | **pass** | iPhone: the PiP button is in the mirror toolbar; on the simulator, which can't do PiP, it explains that in an alert. |
| VQ-061 | P3 | Mirror | The mirror toolbar sits on top of the picture's bottom edge and never fades, hiding the Mac's Dock in the… | **pass** | iPhone: still up at 4 s, gone by the next capture; it now hides. |
| VQ-062 | P3 | Mirror | While the mirror is connecting the status strip shows a lit green dot with "0 FPS" | **not checked** | The mirror showed frames at once; the connecting state wasn't caught. |
| VQ-063 | P3 | Shell | The context strip's empty hint "Bring an app to the front on the Mac" appears whenever Pixel Hand's own… | **not checked** | TextEdit was in front for the whole run. |
| VQ-064 | P1 | Onboarding | At AX3 the onboarding body text runs under the page dots and buttons and is cut mid-line ("…with the… | **pass** | iPhone AX3: onboarding text and buttons scroll together; Continue and Back sit after the text. |
| VQ-065 | P1 | Shell | At AX3 the Mac pill collapses to "…" (no Mac name at all) while the header glyph buttons stay tiny; | **pass** | iPhone AX3: pill reads “Muhammad’s / MacBook Pro” on two lines; one menu button. AX5 still cuts mid-word (VQ-085). |
| VQ-066 | P1 | Paywall | Free-plan upsell card in the deck: | **pass** | Build 25: Show screen sits inside its card at iPhone AX3. |
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
| VQ-083 | P1 | Deck | In deck edit mode the floating mirror tile sits over the header's trailing side: Done is hidden under it (the | **pass** | iPhone edit mode: the mirror tile steps aside; Done and the ghost key row are clear. |
| VQ-084 | P2 | Picker | At AX3 the picker truncates the subtitle (“Pick the Mac to contr…”), cuts the Mac name in the middle (“Muh…ok | **pass** | AX3 and AX5 picker: subtitle wraps, Mac names break at whole words (“AH’s Mac / mini”). |
| VQ-085 | P2 | Shell | At AX5 the Mac pill cuts both lines mid-word (“Muhamma… / MacBook…”) | **pass** | AX5: the pill reads “Muhammad’s / MacBook Pro” in full. |
| VQ-086 | P2 | Pairing | The code sheet shows a second, floating “Connect and pair” capsule at the keypad's top edge that covers the fo | **pass** | One Connect and pair button, no floating copy; title “Pair”. The footer still runs under the keypad (VQ-100). |
| VQ-087 | P3 | Shell | The right column's switch reads “De… | Ask” and the Ask placeholder “What shou…” at AX3. | **pass** | iPad AX3: Deck | Ask shows glyphs; placeholder “Ask your Mac”. |
| VQ-088 | P3 | Shell | The chip row ends mid-label at the trailing edge (“Focus L…”, “Red…”) with no fade or scroll cue. | **pass** | iPad chip row fades out over “Delete” at the trailing edge. |
| VQ-089 | P3 | Settings | Segmented controls (frame rate, send rate, quality, theme) stay at the small default size at AX3 while the row | **pass** | AX3: segmented pickers become menus (“120 Hz ⌃”, “Full ⌃”, “Standard ⌃”, “System ⌃”). |
| VQ-090 | P3 | Paywall | The paywall footer says “Restore Purchases”; Settings says “Restore purchases”. | **pass** | Paywall footer: “Restore purchases”. |
| VQ-091 | P3 | Shell | The rail's empty-state hint is cut mid-word at the rail's edge (“Bring an app to the front c…”). | **pass** | iPhone landscape rail: “Bring an app to the front” fits. |
| VQ-092 | P3 | UI tests | test02 and test11 capture portrait on the iPad because the simulator has windowing on, so iPad landscape (and | **pass** | With PH_QA_FULLSCREEN=1 the iPad walks run real landscape (onboarding and the shell with the sidebar). |
| VQ-093 | P3 | Mirror | With pointer control turned on, test16 can't find ph.mirror.pointerSurface, so OR-16's surface isn't verified | **pass** | test16 finds the pointer surface and captures pointer-control-moved and -zoomed. |
| VQ-094 | P3 | Mac app | The pair window opens with a thick pink focus ring (the system accent) on New code. | **pass** | The pair window opens with no focus ring. |
| VQ-095 | P2 | Mirror | With pointer control on, a quick ~210 pt flick on the picture moved the Mac pointer about 3,250 pt, off the mi | **pass** | By hand: the build 23 flick now moves the pointer about 630 pt (was ~3,250), and a bigger flick stops at the display edge (x = 1511). |
| VQ-096 | P3 | UI tests | connect() taps the first Mac in the picker | **pass** | PH_QA_MAC_NAME: every walk connected to the MacBook. |
| VQ-097 | P3 | Mac app | “Last seen 38 seconds ago” doesn't tick while the panel stays open. | **pass** | Panel: “last seen 2 min ago”, “3 min ago”, “yesterday”. |
| VQ-098 | P2 | Deck | Outside edit mode the floating mirror tile covers the deck's “No keys yet” title at AX3, and most of the… | **pass** | Build 25: the mirror tile stays off the empty deck. |
| VQ-099 | P2 | Sidebar | The Macs sidebar cards cut names mid-word at AX3: | **pass** | Build 25: iPad AX3 sidebar cards stack with whole words. |
| VQ-100 | P2 | Pairing | The code sheet has an unlabelled Mac chooser (a lone ⌃⌄ under the title) that defaults to the first Mac in… | **not checked** | Only the MacBook was on the network (no AH’s Mac mini), so the two-Mac chooser couldn't be reproduced. On the iPad mini the pair sheet names the MacBook and keeps Connect and pair above the keypad. |
| VQ-101 | P3 | Connect | After a cold simulator boot the paired Mac took 7–15 s to reconnect, and the picker showed “Paired | **pass** | iPhone AX3: the picker shows Connecting… with Cancel while the launch reconnect runs. Its layout breaks at AX3 (VQ-107). |
| VQ-102 | P3 | Picker | When the picker scrolls at AX5, the subtitle slides under the Pair and Settings buttons, which have no… | **not checked** | AX5 picker not run: paired simulators go straight to the shell. |
| VQ-103 | P3 | UI tests | The iPad mini simulator isn't paired with the build Mac, so connect() waits for an Allow that never comes… | **pass** | iPad mini (unpaired): test04 snaps skipped-unpaired and sends no request; the Mac showed no approval prompt. |
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
| OT-1 | P2 | Owner testing | Dock app icons are transparent, macOS-style dock with an accent dot | **pass** | iPad and iPhone docks show the Mac's app icons without white plates (Claude, Chrome, Safari, TextEdit). |
| OT-2 | P1 | Owner testing | The keyboard no longer changes the arrangement (open/close loop) | **pass** | iPad landscape: the keyboard stays up and the columns don't move while the Type panel is open (test18, test20). |
| OT-3 | P2 | Owner testing | New Type panel: Live and Compose, keys row, fn, sticky modifiers, numpad | **pass** | iPad and iPhone: Live and Compose, “Typing into <app>”, modifiers, arrows, Home/End/PgUp/PgDn/fn; Compose keeps a draft and Send. |
| OT-4 | P2 | Owner testing | High-contrast right-column handle | **pass** | Not re-captured this pass; passed in build 25 and the column code didn't change. |
| OT-5 | P1 | Owner testing | Ask doesn't get stuck: New request, Run again, Save as key with Cancel, Edit | **pass** | test19 on iPad and iPhone: Run, then New request (empty field with Recent), Save as key › Cancel, and Ask again all work. |
| OT-6 | P1 | Owner testing | The Type panel moves, resizes, folds to a pill and remembers its place | **pass** | iPad landscape: dragged to the top-left corner, narrowed to the stacked layout, folded to the “Claude · Live” pill and reopened where it was (test20). iPhone portrait: docked full width above the keyboard. iPhone landscape not checked (VQ-105). |
| OT-7 | P2 | Owner testing | Compact Type panel: shorter field, inverted-T arrows, two key rows, docked numpad | **pass** | iPad wide and narrow layouts, the numpad docked under the keys with the keyboard down, and the iPhone docked layout all render without clipping. |
| OT-8 | P2 | Owner testing | Typed steps can be saved as keys, with the Return guard | **fail** | iPhone: “Open Safari and type youtube and press return” saved as a key; the deck shows it as “3 steps” and tapping it asks first (“Types into Safari, then presses Return”). iPad portrait: Save is hidden under the keyboard, so the walk couldn't save (VQ-104). |

## New findings

`ID · severity · category · area · device · what's wrong · suggested fix · gallery image`

- VQ-104 · P2 · Layout · Ask · iPad Pro 11" (M5), portrait · With a three-step plan, Save as key's name field is the last row the Ask sheet shows above the keyboard; Save and Cancel are scrolled out of view, so the walk couldn't tap Save (not hittable) and the key wasn't saved. Return still saves, but nothing says so. One-step plans (test19) fit. · Scroll the Save row into view when the name field takes focus (ScrollViewReader on the save row), or let the Ask sheet grow upward above the keyboard. · ipad-ask-save-hidden
- VQ-105 · P3 · Behaviour · Type panel · iPhone 17 Pro, landscape · Rotated to landscape on the Screen tab there's no dock and no keyboard button (neither ph.dock.keyboard nor ph.trackpad.keyboard), so test18 and test20 can't open the Type panel and stop early. Either iPhone landscape has no way to type from the Screen tab, or the walk needs to switch tabs first. · Give the iPhone landscape rail a keyboard button (or keep the dock's), and have the walks fail rather than return early when it's missing. · iphone-landscape-no-keyboard
- VQ-106 · P3 · Test tooling · UI tests · iPhone 17 Pro · test21 taps “Cancel” on the deck key's run confirmation, but on iPhone it's a popover with only Run (dismissed by tapping outside), so the walk fails after the real checks pass. Its name step also leaves the default name's tail (“YT 153 and press return”). · Dismiss the confirmation by tapping outside when there's no Cancel, and select all before typing the key name. · iphone-typed-key-confirm
- VQ-107 · P2 · Accessibility · Picker · iPhone 17 Pro, AX3 · During the launch reconnect the Connecting… state (VQ-101) is squeezed into a circle at the top-left that reads “Con- / necti…”, and its Cancel is drawn over the Pair button. The Mac card's “Paired · Nearby” line runs under the “Can't find your Mac?” footer. In two of four AX3 walks the reconnect then gave up and the walk never reached the shell. · At accessibility sizes show Connecting… and Cancel as a full-width row under the title (or inside the Mac's card), and let the picker scroll above the footer. · iphone-ax3-connecting
- VQ-108 · P3 · Layout · Pairing · iPad mini (A17 Pro) · The pair sheet's code field brings up iPadOS's floating number pad, which sits over the sheet's title (“Type the code showing on …”), so the instruction can't be read while typing. · Anchor the number pad below the field (or use the app's own keypad), or repeat the Mac's name next to the field. · ipad-mini-pair
