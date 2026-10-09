"""Builds website/public/index.html and website/public/ui.css.

Takes the page source in website/src/index.html and swaps each product shot
for an HTML rebuild of the real app screen, matched to the SwiftUI views
(sizes, colours and strings come from DeckHandTheme, ControlView,
TrackpadView, MirrorThumbnailView, QuickActionsBar, StreamDeckGridView,
PeerPickerView, ScreenshotPreviewView and MacMenuBarView).

    python3 website/tools/mockups/build.py

Sizes in ui.src.css are SwiftUI points written as {N}.
"""
import re, pathlib, sys
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mac as macmod
SRC = HERE.parents[1] / 'src' / 'index.html'
WEB = HERE.parents[1] / 'public'

def pts(s):
    return re.sub(r'\{(-?\d+(?:\.\d+)?)\}', lambda m: f'calc({m.group(1)} * var(--pt))', s)

css = pts((HERE / 'ui.src.css').read_text())
css += """
.ui svg { stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
.gbtn svg, .shot__bar svg { stroke-width: 1.1; }
"""
css += macmod.mac_css()
(WEB / 'ui.css').write_text(css)

# ---------- SF Symbol stand-ins ----------
S = {
 'mirror': '<rect x="3" y="8" width="14" height="11" rx="2"/><path d="M7 8V6a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2"/>',
 'mirror-fill': '<path fill="currentColor" stroke="none" d="M9 3h10a2 2 0 012 2v8a2 2 0 01-2 2h-1V10a3 3 0 00-3-3H7V5a2 2 0 012-2z"/><rect fill="currentColor" stroke="none" x="3" y="8.5" width="14" height="11" rx="2"/>',
 'viewfinder': '<path d="M3 8V5.5A2.5 2.5 0 015.5 3H8M16 3h2.5A2.5 2.5 0 0121 5.5V8M21 16v2.5a2.5 2.5 0 01-2.5 2.5H16M8 21H5.5A2.5 2.5 0 013 18.5V16"/><rect x="7" y="9" width="10" height="7.5" rx="1.6"/><circle cx="12" cy="12.8" r="2"/><path d="M10 9l.9-1.5h2.2L14 9"/>',
 'chev-down': '<path d="M5 9l7 7 7-7"/>',
 'gear': '<path d="M21.41 10.09 L21.41 13.91 L18.97 14.16 L18.46 15.41 L20.00 17.30 L17.30 20.00 L15.41 18.46 L14.16 18.97 L13.91 21.41 L10.09 21.41 L9.84 18.97 L8.59 18.46 L6.70 20.00 L4.00 17.30 L5.54 15.41 L5.03 14.16 L2.59 13.91 L2.59 10.09 L5.03 9.84 L5.54 8.59 L4.00 6.70 L6.70 4.00 L8.59 5.54 L9.84 5.03 L10.09 2.59 L13.91 2.59 L14.16 5.03 L15.41 5.54 L17.30 4.00 L20.00 6.70 L18.46 8.59 L18.97 9.84Z"/><circle cx="12" cy="12" r="3.1"/>',
 'minus-circle': '<circle cx="12" cy="12" r="9"/><path d="M8 12h8"/>',
 'hand': '<path d="M9.5 12V4.8a1.6 1.6 0 013.2 0V11m0-1.2a1.6 1.6 0 013.2 0V11m0-.6a1.6 1.6 0 013.1.3V15a6.3 6.3 0 01-6.3 6.3h-.9a6.2 6.2 0 01-5.4-3.1L4.6 14a1.6 1.6 0 012.7-1.7L9.5 15"/>',
 'grid32': '<rect x="2.5" y="5" width="5.4" height="6" rx="1.4"/><rect x="9.3" y="5" width="5.4" height="6" rx="1.4"/><rect x="16.1" y="5" width="5.4" height="6" rx="1.4"/><rect x="2.5" y="13" width="5.4" height="6" rx="1.4"/><rect x="9.3" y="13" width="5.4" height="6" rx="1.4"/><rect x="16.1" y="13" width="5.4" height="6" rx="1.4"/>',
 'updown': '<path d="M12 3v18M8 7l4-4 4 4M8 17l4 4 4-4"/>',
 'tortoise': '<path d="M4 15a7 5.5 0 0114 0z"/><path d="M18 15h1.5a2.5 2.5 0 000-5H18M6.5 15v3M15.5 15v3"/>',
 'hare': '<path d="M3 18c.5-4 3.5-6 8-6h2.5l1.5-6c1.5 1 1.8 3.5 1 5.5 2.6.6 4 2.4 4 4.5 0 1.2-.8 2-2 2H3z"/><path d="M15 6l-1-3"/>',
 'scroll': '<path d="M8 4h10.5A2.5 2.5 0 0121 6.5V8h-4"/><path d="M8 4a2.5 2.5 0 00-2.5 2.5V18a2.5 2.5 0 002.5 2.5h7a2.5 2.5 0 002.5-2.5V6.5A2.5 2.5 0 0015 4"/><path d="M8.8 10h5.5M8.8 13h5.5M8.8 16h3.5"/>',
 'click': '<path d="M10 9v12l3-3 2.4 4.6 1.9-1-2.3-4.4h4.3z"/><path d="M5.5 7.5L7.6 9M8.4 3.8l.7 2.6M3.5 12.2l2.5-.4"/>',
 'click2': '<path d="M10 9v12l3-3 2.4 4.6 1.9-1-2.3-4.4h4.3z"/><path d="M5.5 7.5L7.6 9M8.4 3.8l.7 2.6M3.5 12.2l2.5-.4M3.3 5l1.4 1.1M12.1 3.6l-.4 1.8"/>',
 'click-clock': '<path d="M8 9v12l3-3 2.4 4.6 1.9-1-2.3-4.4h4.3z"/><circle cx="17.5" cy="6.5" r="4"/><path d="M17.5 4.7v1.9l1.3.9"/>',
 'scope': '<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="1.6"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
 'mission': '<rect x="2.5" y="8.5" width="14" height="11" rx="2"/><path d="M2.5 12h14"/><path d="M7 8.5V6.5a2 2 0 012-2h10.5a2 2 0 012 2v8a2 2 0 01-2 2h-3"/>',
 'menubar': '<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M3 8.5h18"/>',
 'x-dark': '<circle cx="12" cy="12" r="10.5" fill="rgba(0,0,0,.55)" stroke="none"/><path d="M8.5 8.5l7 7M15.5 8.5l-7 7" stroke="#fff" stroke-width="2.1"/>',
 'chevl-dark': '<circle cx="12" cy="12" r="10.5" fill="rgba(0,0,0,.45)" stroke="none"/><path d="M13.6 7.4L9 12l4.6 4.6" stroke="#fff" stroke-width="2.3"/>',
 'chevr-dark': '<circle cx="12" cy="12" r="10.5" fill="rgba(0,0,0,.45)" stroke="none"/><path d="M10.4 7.4L15 12l-4.6 4.6" stroke="#fff" stroke-width="2.3"/>',
 'x-hier': '<circle cx="12" cy="12" r="10.5" fill="currentColor" stroke="none" opacity=".35"/><path d="M8.5 8.5l7 7M15.5 8.5l-7 7" stroke="currentColor" stroke-width="2.1"/>',
 'wifi': '<path d="M2 9a14.5 14.5 0 0120 0M5.2 12.4a9.6 9.6 0 0113.6 0M8.6 15.8a4.8 4.8 0 016.8 0" stroke-width="2.4"/><circle cx="12" cy="19.2" r="1.5" fill="currentColor" stroke="none"/>',
 'save': '<path d="M8 9H6.5A2.5 2.5 0 004 11.5v7A2.5 2.5 0 006.5 21h11a2.5 2.5 0 002.5-2.5v-7A2.5 2.5 0 0017.5 9H16"/><path d="M12 3v12M8 11l4 4 4-4"/>',
 'copy': '<rect x="8" y="7" width="11.5" height="14" rx="2.2"/><path d="M5 16.5V5.2A2.2 2.2 0 017.2 3H15"/>',
 'share': '<path d="M8 9H6.5A2.5 2.5 0 004 11.5v7A2.5 2.5 0 006.5 21h11a2.5 2.5 0 002.5-2.5v-7A2.5 2.5 0 0017.5 9H16"/><path d="M12 15V3M8 7l4-4 4 4"/>',
 'pencil-tip': '<path d="M12 2.8l5 9.2v8a1 1 0 01-1 1H8a1 1 0 01-1-1v-8z"/><path d="M7 12h10M10.4 6.6h3.2"/>',
 'text-vf': '<path d="M3 8V5.5A2.5 2.5 0 015.5 3H8M16 3h2.5A2.5 2.5 0 0121 5.5V8M21 16v2.5a2.5 2.5 0 01-2.5 2.5H16M8 21H5.5A2.5 2.5 0 013 18.5V16"/><path d="M8 9h8M8 12h8M8 15h5"/>',
 'scissors': '<circle cx="6" cy="7" r="2.6"/><circle cx="6" cy="17" r="2.6"/><path d="M8.2 8.4L20 18M8.2 15.6L20 6"/>',
 'paste': '<rect x="5" y="4.5" width="14" height="16.5" rx="2.2"/><path d="M9 4.5V3.5h6v1"/><path d="M9 10.5h6M9 14.5h6"/>',
 'undo': '<path d="M9 6L4.5 10.5 9 15"/><path d="M4.5 10.5h10a5 5 0 010 10H12"/>',
 'redo': '<path d="M15 6l4.5 4.5L15 15"/><path d="M19.5 10.5h-10a5 5 0 000 10H12"/>',
 'select': '<rect x="4" y="4" width="16" height="16" rx="2.5" stroke-dasharray="3 2.6"/><path d="M9 12h6"/>',
 'delete': '<path d="M9 5h10a2 2 0 012 2v10a2 2 0 01-2 2H9l-6.5-7z"/><path d="M11.2 9.5l5 5M16.2 9.5l-5 5"/>',
 'return': '<path d="M19 4.5v6.5a3 3 0 01-3 3H5.5M9.5 10l-4 4 4 4"/>',
 'bubble-x': '<path fill="currentColor" stroke="none" d="M4.5 3h15A2.5 2.5 0 0122 5.5v9a2.5 2.5 0 01-2.5 2.5H12l-5 4v-4H4.5A2.5 2.5 0 012 14.5v-9A2.5 2.5 0 014.5 3z"/><path d="M12 6.5v4.6M12 13.6v.2" stroke="#fff" stroke-width="2.3"/>',
 'desktop': '<rect x="2" y="3" width="20" height="13.5" rx="2.2"/><path d="M9 21h6M12 16.5V21"/>',
 'chev-r': '<path d="M9 5l7 7-7 7" stroke-width="2.6"/>',
 'check-fill': '<circle cx="12" cy="12" r="10.5" fill="currentColor" stroke="none"/><path d="M7.4 12.4l3 3 6.1-6.6" stroke="#25232f" stroke-width="2.4"/>',
 'xc-fill': '<circle cx="12" cy="12" r="10.5" fill="currentColor" stroke="none"/><path d="M8.6 8.6l6.8 6.8M15.4 8.6l-6.8 6.8" stroke="#25232f" stroke-width="2.4"/>',
 'warn-fill': '<path fill="currentColor" stroke="none" d="M10.3 3.4a2 2 0 013.4 0l9 15.6a2 2 0 01-1.7 3H3a2 2 0 01-1.7-3z"/><path d="M12 9v5M12 17.4v.2" stroke="#25232f" stroke-width="2.4"/>',
 'ipad': '<rect x="4.5" y="2.5" width="15" height="19" rx="2.6"/><path d="M11 18.6h2"/>',
 'rays': '<path d="M10 9v12l3-3 2.4 4.6 1.9-1-2.3-4.4h4.3z" fill="currentColor"/><path d="M5.5 7.5L7.6 9M8.4 3.8l.7 2.6M3.5 12.2l2.5-.4M14 3.5l-.8 2.4M18.4 6.6l-2 1.5"/>',
 'search': '<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5L21 21"/>',
 'grid33': '<g fill="currentColor" stroke="none"><rect x="3" y="3" width="5" height="5" rx="1.2"/><rect x="9.5" y="3" width="5" height="5" rx="1.2"/><rect x="16" y="3" width="5" height="5" rx="1.2"/><rect x="3" y="9.5" width="5" height="5" rx="1.2"/><rect x="9.5" y="9.5" width="5" height="5" rx="1.2"/><rect x="16" y="9.5" width="5" height="5" rx="1.2"/><rect x="3" y="16" width="5" height="5" rx="1.2"/><rect x="9.5" y="16" width="5" height="5" rx="1.2"/><rect x="16" y="16" width="5" height="5" rx="1.2"/></g>',
 'back': '<path fill="currentColor" stroke="none" d="M11.5 6v12L3 12zM21.5 6v12L13 12z"/>',
 'playpause': '<path fill="currentColor" stroke="none" d="M2.5 6v12l8.5-6z"/><rect x="13.5" y="6" width="3" height="12" rx="1" fill="currentColor" stroke="none"/><rect x="18.5" y="6" width="3" height="12" rx="1" fill="currentColor" stroke="none"/>',
 'fwd': '<path fill="currentColor" stroke="none" d="M2.5 6v12l8.5-6zM12.5 6v12l8.5-6z"/>',
 'chevdown-sm': '<path d="M6 9.5l6 6 6-6" stroke-width="2.6"/>',
 'antenna': '<circle cx="12" cy="11" r="2"/><path d="M8 7a5.6 5.6 0 000 8M16 7a5.6 5.6 0 010 8M5 4.5a9.5 9.5 0 000 13M19 4.5a9.5 9.5 0 010 13M12 13v8"/>',
}
SPRITE = '<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs><linearGradient id="litg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9E7BFF"/><stop offset=".5" stop-color="#7C5CFF"/><stop offset="1" stop-color="#6E86FF"/></linearGradient></defs>' + \
    ''.join(f'<symbol id="i-{k}" viewBox="0 0 24 24" fill="none" stroke="currentColor">{v}</symbol>' for k, v in S.items()) + \
    '<symbol id="i-battery" viewBox="0 0 28 13" fill="none" stroke="currentColor"><rect x="1" y="1" width="22.5" height="11" rx="3.2" opacity=".4" stroke-width="1.2"/><rect x="3" y="3" width="18.5" height="7" rx="1.6" fill="currentColor" stroke="none"/><path d="M26 4.8v3.4" stroke-width="1.6" opacity=".5"/></symbol></svg>'

def ic(name, cls='', style=''):
    c = f' class="{cls}"' if cls else ''
    st = f' style="{style}"' if style else ''
    return f'<svg{c}{st} aria-hidden="true"><use href="#i-{name}"/></svg>'

# ---------- Shared pieces ----------
MAC = macmod.desktop()

APPS = {  # slug, fallback tint (shown until website/tools/fetch-apple-assets.sh adds the real icon)
 'Xcode': ('xcode', '#5ac8fa,#007aff'), 'Keynote': ('keynote', '#7fc8ff,#1f6fe5'), 'Pages': ('pages', '#ffcf8a,#ff9500'),
 'Numbers': ('numbers', '#7ee08a,#22a447'), 'Final Cut Pro': ('final-cut-pro', '#4a4a52,#1c1c22'), 'Logic Pro': ('logic-pro', '#5b5b66,#24242b'),
 'Pixelmator Pro': ('pixelmator-pro', '#ff9b7a,#a259ff'), 'Slack': ('slack', '#c79cff,#7c3aed'),
}
def appi(name):
    slug, tint = APPS[name]
    a, b = tint.split(',')
    return (f'<i class="appicon" style="background:linear-gradient(160deg,{a},{b})">'
            f'<img src="assets/apps/{slug}.png" alt="" loading="lazy" onload="this.parentNode.classList.add(\'has-icon\')" onerror="this.remove()"></i>')

def status_bar(phone=False):
    if phone:
        return f'<div class="sbar sbar--phone"><span>9:41</span><span class="sbar__r">{ic("wifi")}<svg style="width:calc(26*var(--pt));height:calc(12*var(--pt))" aria-hidden="true"><use href="#i-battery"/></svg></span></div>'
    return f'<div class="sbar"><span>9:41&nbsp;&nbsp;Thu Oct 9</span><span class="sbar__r">{ic("wifi")}<span>100%</span><svg style="width:calc(25*var(--pt));height:calc(12*var(--pt))" aria-hidden="true"><use href="#i-battery"/></svg></span></div>'

def nav_bar(mac, app, mirror_on=True):
    mirror = f'<span class="anav__btn nav__btn--violet">{ic("mirror-fill")}</span>' if mirror_on else f'<span class="anav__btn">{ic("mirror")}</span>'
    return (f'<div class="anav"><div class="anav__title"><span class="anav__name">{mac}</span>'
            f'<span class="anav__status"><i class="anav__dot"></i>{app}</span><span class="anav__session">session 3F2A9C1B</span></div>'
            f'{mirror}<span class="anav__btn">{ic("viewfinder")}{ic("chev-down","sm")}</span>'
            f'<span class="anav__btn">{ic("gear")}</span><span class="anav__btn nav__btn--red">{ic("minus-circle")}</span></div>')

def seg(tab='trackpad'):
    a = ' class="on"' if tab == 'trackpad' else ''
    b = ' class="on"' if tab == 'apps' else ''
    return f'<div class="seg"><span{a}>{ic("hand")}Trackpad</span><span{b}>{ic("grid32")}Apps</span></div><div class="hair"></div>'

GESTURES = [('Scroll','scroll','var(--emerald)'),('Left Click','click','var(--violet)'),('Right Click','click2','var(--violet-soft)'),
            ('Double Click','click-clock','var(--indigo)'),('Locate','scope','var(--violet)'),('Mission','mission','var(--sky)'),('Desktop','menubar','var(--mint)')]
def gesture_bar(scroll_on=False):
    out = '<div class="gbar">'
    for i,(label,icon,col) in enumerate(GESTURES):
        cls = 'gbtn' + (' gbtn--scroll' if i == 0 else '') + (' on' if i == 0 and scroll_on else '')
        out += f'<span class="{cls}" style="--g:{col}">{ic(icon)}<span>{label}</span></span>'
    return out + '</div>'

def sensitivity():
    ticks = ''.join(f'<span{" class=on" if t=="1.5×" else ""}>{t}</span>' for t in ['0.75×','1×','1.5×','2×','3×'])
    return (f'<div class="sens"><div class="sens__row">{ic("tortoise")}<span class="sens__track"></span>{ic("hare")}'
            f'<span class="sens__val">1.5×</span></div><div class="sens__ticks">{ticks}</div></div>')

def mirror(style, chevrons=True):
    ch = (f'{ic("chevl-dark","mirror2__chev mirror2__chev--l")}{ic("chevr-dark","mirror2__chev mirror2__chev--r")}' if chevrons else '')
    return f'<div class="mirror2" style="{style}">{MAC}{ic("x-dark","mirror2__x")}{ch}</div>'

def surface(capsule=None, ripple=None, hint='Trackpad'):
    cap = ''
    if capsule:
        label, icon, col = capsule
        cap = f'<span class="gcap" style="--g:{col}">{ic(icon)}{label}</span>'
    rip = ''
    if ripple:
        x, y = ripple
        rip = f'<span class="ripple ripple--fade" style="left:{x};top:{y}"></span><span class="ripple" style="left:{x};top:{y}"></span>'
    return (f'<div class="surface">{cap}<div class="surface__hint"><b>{hint}</b>'
            f'<small>Tap • Left  |  Hold • Right  |  2F • Scroll  |  3F • Spaces</small></div>{rip}'
            f'<div class="surface__dots"><i></i><i></i><i></i></div></div>')

def trackpad_screen(theme, mac, app, phone=False, capsule=None, ripple=None, scroll_on=False, mirror_style=None, hint='Trackpad'):
    mir = mirror(mirror_style) if mirror_style else ''
    island = '<span class="island"></span>' if phone else ''
    return (f'<div class="ui ui-{theme}{" phone" if phone else ""}">{island}<div class="ui-col">{status_bar(phone)}'
            f'{nav_bar(mac, app, mirror_on=bool(mirror_style))}{seg()}'
            f'<div class="tp-tab">{surface(capsule, ripple, hint)}{sensitivity()}{gesture_bar(scroll_on)}{mir}</div></div></div>')

def chips(items):
    return '<div class="qchips">' + ''.join(f'<span class="qchip"><b>{k}</b><span>{n}</span></span>' for k, n in items) + '</div>'

def qab_normal(app, items):
    return (f'<div class="qab qab--fade"><span class="qpill">{appi(app)}{app}</span>{ic("chevdown-sm","qchev")}<span class="qab__div"></span>{chips(items)}'
            f'<span class="qab__div"></span><span class="qicons"><span>{ic("mission")}</span><span>{ic("grid33")}</span><span>{ic("menubar")}</span></span>'
            f'<span class="qab__div"></span><span class="qicons"><span>{ic("back")}</span><span>{ic("playpause")}</span><span>{ic("fwd")}</span></span></div>')

def qab_dialog(app):
    return (f'<div class="qab"><span class="qpill">{appi(app)}{app}</span><span class="qab__div"></span><span class="qinfo">{ic("bubble-x")}</span><span class="qspacer"></span>'
            f'<span class="qdlg">Don’t Save</span><span class="qdlg qdlg--cancel">Cancel</span><span class="qdlg qdlg--default">Save <small>⏎</small></span></div>')

def qab_edit(app):
    edits = [('scissors','Cut'),('copy','Copy'),('paste','Paste'),('undo','Undo'),('redo','Redo'),('select','All'),('delete','Delete')]
    e = ''.join(f'<span class="qedit">{ic(i)}<span>{n}</span></span>' for i, n in edits)
    return (f'<div class="qab qab--scrolled"><span class="qpill" style="margin-left:calc(-470*var(--pt))">{appi(app)}{app}</span><span class="qab__div"></span>'
            f'{chips([("⌘K","Quick Switcher"),("⌘⇧T","Threads"),("⌘⇧D","Sidebar")])}<span class="qab__div qab__div--short"></span>'
            f'<div class="qchips qchips--tight">{e}<span class="qedit qedit--go">{ic("return")}<span>Return</span></span></div></div>')

XCODE = [('⌘B','Build'),('⌘R','Run'),('⌘.','Stop'),('⌘⇧K','Clean Build'),('⌘⇧O','Open Quickly'),('⌘⇧F','Find in Workspace')]

# ---------- Screens ----------
HERO = ('<div class="dev-ipad" role="img" aria-label="Deck Hand on an iPad in dark mode: the Trackpad tab with a tap ripple, the sensitivity slider, '
        'the gesture bar, and the live mirror of the Mac expanded in the corner.">'
        + trackpad_screen('dark', 'Junaid’s MacBook Pro', 'Xcode', capsule=('Cursor','hand','var(--violet)'), ripple=('27%','44%'),
                          mirror_style='right:{16};bottom:{96};width:{470};aspect-ratio:16/10') + '</div>')

PHONE_TP = ('<div class="dev-iphone" role="img" aria-label="Deck Hand on an iPhone in light mode, scrolling with two fingers: the Scroll button is lit and the trackpad shows a Scrolling badge.">'
            + trackpad_screen('light', 'Studio Mac', 'Safari', phone=True, capsule=('Scrolling','updown','var(--emerald)'), scroll_on=True, hint='Scroll Mode') + '</div>')

MIRROR_IPAD = ('<div class="dev-ipad" role="img" aria-label="The live mirror pinched up to most of the iPad screen, with arrows to switch Spaces on the Mac.">'
               + trackpad_screen('dark', 'Junaid’s MacBook Pro', 'Xcode', mirror_style='left:{120};top:{150};width:{900};aspect-ratio:16/10') + '</div>')

ANNOT = ('<svg class="ink" viewBox="0 0 160 100" preserveAspectRatio="none" aria-hidden="true" fill="none" stroke="#FF453A" stroke-width="1.6" stroke-linecap="round">'
         '<ellipse cx="80" cy="34.7" rx="18" ry="4.6" transform="rotate(-3 80 34.7)"/><path d="M40 72c12-8 22-18 32-30"/><path d="M66 41.5l6.4.2-.4 6.2"/></svg>')
CAPTURE = ('<div class="dev-ipad" role="img" aria-label="A screenshot of the Mac open on the iPad with a red annotation, an Annotated badge, a Saved to Photos toast, and buttons for Save, Copy, Share, Annotate and Text.">'
           '<div class="ui ui-dark shot"><div class="ui-col">' + status_bar() + '</div>'
           f'<span class="shot__badge">Annotated</span>{ic("x-hier","shot__x")}'
           f'<div class="shot__img">{MAC}{ANNOT}</div>'
           '<span class="shot__toast">Saved to Photos ✓</span>'
           '<div class="shot__bar">' + ''.join(f'<span>{ic(i)}{n}</span>' for i, n in [('save','Save'),('copy','Copy'),('share','Share'),('pencil-tip','Annotate'),('text-vf','Text')]) +
           '</div></div></div>')

def panel(inner, width, theme='light', extra=''):
    return f'<div class="ui ui-{theme} apanel" style="--pt: calc(100cqw / {width}){extra}">{inner}</div>'

BENTO_MENU = panel(f'<div class="qhead">QUICK ACTIONS</div><div style="padding:0 calc(20*var(--pt)) calc(20*var(--pt))">{qab_normal("Xcode", XCODE)}</div>', 300)
BENTO_DIALOG = ('<div class="menu-arrow" aria-hidden="true"><div class="macpane" style="--mp: calc(100cqw / 540)">' + macmod.alert('Q3 Review') + '</div>'
                + panel(f'<div style="padding:calc(14*var(--pt))">{qab_dialog("Pages")}</div>', 430) + '</div>')
grid_apps = ['Xcode','Keynote','Pages','Numbers','Final Cut Pro','Logic Pro','Pixelmator Pro','Slack']
BENTO_GRID = panel(f'<div class="search">{ic("search")}Search apps</div><div class="qhead">ALL APPS</div><div class="agrid">'
                   + ''.join(f'<span class="atile{" front" if a=="Xcode" else ""}">{appi(a)}{a}</span>' for a in grid_apps)
                   + '</div><div style="height:calc(22*var(--pt))"></div>', 380)
BENTO_EDIT = panel(f'<div style="padding:calc(16*var(--pt)) calc(20*var(--pt))">{qab_edit("Slack")}</div>', 345)

PEERS = ('<div class="dev-iphone" role="img" aria-label="The Deck Hand picker on iPhone: Choose a Mac to control, with Junaid’s MacBook Pro marked My Mac and Studio Mac, both nearby.">'
         '<div class="ui ui-dark picker phone"><span class="island"></span><div class="ui-col">' + status_bar(True) + '</div>'
         f'<span class="picker__gear">{ic("gear")}</span><div class="picker__col"><div class="picker__head">'
         '<img class="picker__mark" src="assets/icon-256.png" alt="">'
         '<div><div class="picker__title">Deck Hand</div><div class="picker__sub">Choose a Mac to control</div></div></div>'
         '<div class="peers">'
         f'<div class="peer peer--busy"><span class="peer__icon"><svg aria-hidden="true" style="width:calc(22*var(--pt));height:calc(20*var(--pt))" stroke="url(#litg)" fill="none" stroke-width="2"><use href="#i-desktop"/></svg></span><span class="peer__text"><span class="peer__name">Junaid’s MacBook Pro<span class="peer__badge">My Mac</span></span><span class="peer__where"><i></i>Nearby</span></span><span class="peer__spin"></span></div>'
         f'<div class="peer" style="opacity:.4"><span class="peer__icon"><svg aria-hidden="true" style="width:calc(22*var(--pt));height:calc(20*var(--pt))" stroke="url(#litg)" fill="none" stroke-width="2"><use href="#i-desktop"/></svg></span><span class="peer__text"><span class="peer__name">Studio Mac</span><span class="peer__where"><i></i>Nearby</span></span>{ic("chev-r","peer__chev")}</div>'
         f'</div></div><div class="picker__foot">{ic("wifi")}Both devices on the same Wi-Fi</div></div></div>')

def perm(title, detail):
    return f'<div class="mperm">{ic("check-fill","", "color:var(--success);width:calc(13*var(--pt));height:calc(13*var(--pt))")}<div><b>{title}</b><span>{detail}</span></div></div>'
POPOVER = ('<div class="macbar" aria-hidden="true"><span class="macbar__item">' + ic('rays') + '</span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="5" width="18" height="6" rx="3"/><circle cx="16" cy="8" r="1.6" fill="currentColor"/><rect x="3" y="13" width="18" height="6" rx="3"/><circle cx="8" cy="16" r="1.6" fill="currentColor"/></svg><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M2 9a14.5 14.5 0 0120 0M5.2 12.4a9.6 9.6 0 0113.6 0M8.6 15.8a4.8 4.8 0 016.8 0"/><circle cx="12" cy="19.2" r="1.5" fill="currentColor" stroke="none"/></svg><span class="macbar__time">9:41 AM</span></div>'
           '<div class="mpop-wrap"><div class="mpop ui" role="img" aria-label="The Deck Hand menu on the Mac showing a pending request from Junaid’s iPad with approve and decline buttons, and all permissions granted.">'
           f'<div class="mpop__head"><span class="mpop__logo">{ic("rays")}</span><div><b>Deck Hand</b><small>Ready to receive</small></div></div><div class="mpop__div"></div>'
           '<div class="mpop__h mpop__h--warn">PENDING REQUESTS</div>'
           f'<div class="mrow"><span class="mrow__icon" style="color:#F59E0B">{ic("ipad")}</span><span class="mrow__text"><b>Junaid’s iPad</b><span>Requesting mouse access</span><small>Pending 12 sec ago</small></span>'
           f'<span class="mrow__acts"><span style="color:var(--success)">{ic("check-fill")}</span><span style="color:var(--danger)">{ic("xc-fill")}</span></span></div>'
           '<div class="mpop__div" style="margin-top:calc(6*var(--pt))"></div><div class="mpop__h">PERMISSIONS</div>'
           + perm('Accessibility','Mouse, keyboard, and dialog control') + perm('Screen Recording','Screenshots and live mirror') + perm('Notifications','Connection approval alerts') +
           '<div class="mpop__div" style="margin-top:calc(6*var(--pt))"></div><div class="mpop__quit">Quit Deck Hand</div></div></div>')

# ---------- Patch index.html ----------
html = SRC.read_text()
if 'id="i-hand"' not in html:
    html = html.replace('<a class="skip"', SPRITE + '\n<a class="skip"', 1)
if 'ui.css' not in html:
    html = html.replace('<link rel="stylesheet" href="styles.css">', '<link rel="stylesheet" href="styles.css">\n<link rel="stylesheet" href="ui.css">')
html = html.replace('<link rel="stylesheet" href="ui.css">', '<link rel="stylesheet" href="ui.css">\n<link rel="stylesheet" href="bezels.css">') if 'bezels.css' not in html else html
html = html.replace('family=Google+Sans+Code&display=swap', 'family=Google+Sans+Code&family=Nunito:wght@400;500;600;700&display=swap')

def replace_element(start, new):
    """Replace the whole element that begins at `start` (div depth counting)."""
    global html
    i = html.index(start)
    depth = 0; k = i
    tag = re.match(r'<(\w+)', start).group(1)
    pat = re.compile(r'<(/?)' + tag + r'\b[^>]*>')
    for m in pat.finditer(html, i):
        depth += -1 if m.group(1) else 1
        if depth == 0:
            k = m.end(); break
    html = html[:i] + new + html[k:]

def frame(cls, inner, extra=''):
    return f'<div class="frame {cls} reveal" style="--delay:120ms"><div class="frame__stage{extra}">{inner}</div></div>'

replace_element('<div class="device" role="img"', pts(HERO))
replace_element('<div class="frame frame--violet reveal"', frame('frame--violet frame--phone', pts(PHONE_TP)))
replace_element('<div class="frame frame--teal reveal"', frame('frame--teal frame--ipad', pts(MIRROR_IPAD)))
replace_element('<div class="frame frame--muted reveal"', frame('frame--muted frame--ipad', pts(CAPTURE)))
replace_element('<div class="menu-arrow" aria-hidden="true">\n                <div class="menu">', BENTO_MENU)
replace_element('<div class="menu-arrow" aria-hidden="true">\n                <div class="dialog">', BENTO_DIALOG)
replace_element('<div class="launcher"', BENTO_GRID)
replace_element('<div class="media-keys"', BENTO_EDIT)
replace_element('<div class="link-diagram reveal">', '<div class="duo reveal"><div class="duo__phone">' + pts(PEERS) + '</div><div class="duo__mac">' + pts(POPOVER) + '</div></div>')
html = html.replace('<h3 class="bento__title">Media keys</h3>', '<h3 class="bento__title">Typing help when a field is focused</h3>')
html = html.replace('<p class="bento__text">Play, pause, and skip whatever is playing on the Mac without touching it.</p>',
    '<p class="bento__text">Click into a text field on the Mac and the bar swaps in Cut, Copy, Paste, Undo, and Return. Number fields get a number pad.</p>')
html = html.replace('<div class="hero__stars" aria-hidden="true"></div>', '<div class="hero__stars" aria-hidden="true"></div>\n    <canvas class="hero__pixels" aria-hidden="true"></canvas>')
(WEB / 'index.html').write_text(html)
print('ok', len(html))
