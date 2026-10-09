"""A macOS desktop (1440x900 points) with an Xcode-style editor showing real
Deck Hand code (from DeckHand/Shared/ControlMessage.swift), and a macOS save
alert. Sizes are written as <N> mac points."""
import re, html

CODE = open(__import__('pathlib').Path(__file__).resolve().parents[3] / 'DeckHand' / 'Shared' / 'ControlMessage.swift').read().splitlines()
FIRST = 9
LINES = CODE[FIRST - 1:FIRST - 1 + 36]

KEYWORDS = {'public', 'enum', 'case', 'import', 'let', 'var', 'struct', 'func', 'static', 'private', 'return', 'some', 'init', 'self', 'nil', 'true', 'false'}
SYSTEM_TYPES = {'Codable', 'Sendable', 'Float', 'String', 'Data', 'Int', 'Bool', 'Double', 'Foundation'}
TOKEN = re.compile(r'(?P<doc>///.*)|(?P<com>//.*)|(?P<str>"[^"]*")|(?P<num>\b\d+(?:\.\d+)?\b)|(?P<word>[A-Za-z_][A-Za-z0-9_]*)|(?P<other>.)')

def highlight(line):
    out, prev_kw = [], None
    for m in TOKEN.finditer(line):
        t = m.group(0); e = html.escape(t)
        if m.group('doc') or m.group('com'):
            cls = 'mk' if 'MARK' in t else 'c'
            out.append(f'<span class="{cls}">{e}</span>')
        elif m.group('str'): out.append(f'<span class="s">{e}</span>')
        elif m.group('num'): out.append(f'<span class="n">{e}</span>')
        elif m.group('word'):
            if t in KEYWORDS: out.append(f'<span class="k">{e}</span>'); prev_kw = t; continue
            if prev_kw in ('case', 'enum', 'struct', 'func'): out.append(f'<span class="d">{e}</span>')
            elif t in SYSTEM_TYPES: out.append(f'<span class="t">{e}</span>')
            elif t[0].isupper(): out.append(f'<span class="p">{e}</span>')
            else: out.append(e)
            prev_kw = None; continue
        else: out.append(e)
        if not t.isspace(): prev_kw = None
    return ''.join(out) or '&nbsp;'

APPLE = '<svg viewBox="0 0 17 20" aria-hidden="true"><path fill="currentColor" d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9C3.6 4.8 2 5.8 1.1 7.4c-1.8 3.2-.5 7.9 1.3 10.5.9 1.3 1.9 2.7 3.3 2.6 1.3-.1 1.8-.8 3.4-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.2-2.6 1-1.5 1.4-2.9 1.4-3-.1 0-2.9-1.1-3-4.3zM11.5 2.9C12.2 2 12.7.8 12.6-.4c-1 .1-2.3.7-3 1.6-.7.8-1.3 2-1.1 3.2 1.1.1 2.3-.6 3-1.5z"/></svg>'
FOLDER = '<svg viewBox="0 0 16 13" aria-hidden="true"><path fill="#1E8CFF" d="M1.5 1h4.3l1.5 1.6h7.2c.8 0 1.5.7 1.5 1.5v7.4c0 .8-.7 1.5-1.5 1.5h-13C.7 13 0 12.3 0 11.5v-9C0 1.7.7 1 1.5 1z"/></svg>'
SWIFT = '<svg viewBox="0 0 13 15" aria-hidden="true"><path fill="#fff" stroke="#c7c7cc" stroke-width=".8" d="M1.4.4h7l4.2 4.2v8.8c0 .6-.5 1.2-1.1 1.2H1.4C.8 14.6.4 14 .4 13.4V1.6C.4 1 .8.4 1.4.4z"/><path fill="#F05138" d="M3 7.5h7v4.2H3z" rx="1"/></svg>'

TREE = [
    (0, 'folder', 'DeckHand', ''), (1, 'folder', 'DeckHandMac', ''), (1, 'folder', 'DeckHandiOS', ''), (1, 'folder', 'Shared', ''),
    (2, 'swift', 'AppShortcut.swift', ''), (2, 'swift', 'CaptureMode.swift', ''), (2, 'swift', 'ControlMessage.swift', 'sel'),
    (2, 'swift', 'CuratedShortcuts.swift', ''), (2, 'swift', 'DeckHandCloud.swift', ''), (2, 'swift', 'DeckHandTheme.swift', ''),
    (1, 'folder', 'DeckHandTests', ''), (0, 'folder', 'Loom', ''), (1, 'swift', 'Package.swift', 'mod'),
]

def tree():
    rows = []
    for lvl, kind, name, state in TREE:
        icon = FOLDER if kind == 'folder' else SWIFT
        badge = '<em>M</em>' if state == 'mod' else ''
        rows.append(f'<li class="lv{lvl}{" sel" if state == "sel" else ""}">{icon}<span>{name}</span>{badge}</li>')
    return '<ul class="mac__tree">' + ''.join(rows) + '</ul>'

def code():
    lines = []
    for i, line in enumerate(LINES):
        n = FIRST + i
        cur = ' class="cur"' if n == 14 else ''
        lines.append(f'<li{cur}><i>{n}</i><code>{highlight(line)}</code></li>')
    return '<ol class="mac__code">' + ''.join(lines) + '</ol>'

DOC_ICON = ('<svg class="nsalert__icon" viewBox="0 0 64 64" aria-hidden="true"><path fill="#fff" stroke="#d1d1d6" d="M14 4h26l12 12v42a3 3 0 01-3 3H14a3 3 0 01-3-3V7a3 3 0 013-3z"/>'
            '<path fill="#e5e5ea" d="M40 4v9a3 3 0 003 3h9z"/><rect x="18" y="40" width="28" height="12" rx="3" fill="#F05138"/>'
            '<path d="M18 24h22M18 30h26M18 35h16" stroke="#d1d1d6" stroke-width="2" stroke-linecap="round"/></svg>')

def alert(file='Package.swift'):
    return (f'<div class="nsalert">{DOC_ICON}<b>Do you want to save the changes you made to “{file}”?</b>'
            '<p>Your changes will be lost if you don’t save them.</p>'
            '<span class="nsalert__btns"><i class="def">Save</i><i>Don’t Save</i><i>Cancel</i></span></div>')

WIFI = '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M2 9a14.5 14.5 0 0120 0M5.2 12.4a9.6 9.6 0 0113.6 0M8.6 15.8a4.8 4.8 0 016.8 0"/><circle cx="12" cy="19.2" r="1.5" fill="currentColor" stroke="none"/></svg>'

def desktop():
    menus = ''.join(f'<span>{m}</span>' for m in ['File', 'Edit', 'View', 'Find', 'Navigate', 'Editor', 'Product', 'Debug', 'Window', 'Help'])
    return (f'<div class="mac" aria-hidden="true"><div class="mac__bar">{APPLE}<b>Xcode</b>{menus}<span class="mac__sp"></span>{WIFI}<span>Thu Oct 9&nbsp;&nbsp;9:41 AM</span></div>'
            '<div class="mac__win"><div class="mac__side"><span class="mac__lights"><i></i><i></i><i></i></span>' + tree() + '</div>'
            '<div class="mac__main"><div class="mac__tool"><b>DeckHand</b><span class="mac__scheme">DeckHandMac <s>›</s> My Mac</span><span class="mac__status">Build Succeeded&nbsp;&nbsp;|&nbsp;&nbsp;Today at 9:40 AM</span></div>'
            '<div class="mac__tabs"><span class="on">' + SWIFT + 'ControlMessage.swift</span><span>' + SWIFT + 'Package.swift</span></div>'
            + code() + '</div>' + alert() + '</div></div>')

CSS = """
/* ---------- macOS desktop (1440x900 mac points) ---------- */
.mac { --mp: calc(100cqw / 1440); position: relative; width: 100%; height: 100%; container-type: inline-size; overflow: hidden; font-family: -apple-system, "SF Pro Text", "Inter", system-ui, sans-serif; letter-spacing: 0; text-align: left;
  background: radial-gradient(80% 60% at 70% 110%, #f2b9a3 0%, transparent 60%), radial-gradient(70% 70% at 15% 0%, #3a3fb8 0%, transparent 70%), linear-gradient(170deg, #1d1f5e 0%, #5a54c9 48%, #b98fd6 78%, #f1c1ae 100%); }
.mac svg { display: block; flex: none; }
.mac__bar { height: <30>; display: flex; align-items: center; gap: <18>; padding: 0 <16>; color: #fff; font-size: <13>; font-weight: 400; background: rgba(20, 18, 50, 0.18); -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px); }
.mac__bar > svg:first-child { width: <14>; height: <17>; margin-right: <4>; }
.mac__bar b { font-weight: 700; }
.mac__bar > svg:not(:first-child) { width: <16>; height: <16>; }
.mac__sp { flex: 1; }
.mac__win { position: absolute; left: <110>; top: <62>; width: <1220>; height: <800>; border-radius: <18>; overflow: hidden; display: flex; background: #fff;
  box-shadow: 0 <30> <80> rgba(10, 8, 40, 0.42), 0 0 0 <0.5> rgba(0, 0, 0, 0.25); }
.mac__side { width: <250>; flex: none; background: #ececf0; border-right: <1> solid #dcdce0; padding: <16> <10>; }
.mac__lights { display: flex; gap: <8>; padding: <2> <8> <20>; }
.mac__lights i { width: <13>; height: <13>; border-radius: 50%; background: #ff5f57; box-shadow: inset 0 0 0 <0.5> rgba(0, 0, 0, 0.15); }
.mac__lights i:nth-child(2) { background: #febc2e; } .mac__lights i:nth-child(3) { background: #28c840; }
.mac__tree { list-style: none; margin: 0; padding: 0; font-size: <13>; color: #1d1d1f; }
.mac__tree li { height: <26>; display: flex; align-items: center; gap: <6>; border-radius: <6>; white-space: nowrap; }
.mac__tree li.lv0 { padding-left: <6>; font-weight: 600; } .mac__tree li.lv1 { padding-left: <22>; } .mac__tree li.lv2 { padding-left: <38>; }
.mac__tree li svg { width: <15>; height: <14>; }
.mac__tree li.sel { background: #0a84ff; color: #fff; }
.mac__tree em { margin-left: auto; margin-right: <8>; font-style: normal; font-size: <11>; color: #8e8e93; }
.mac__main { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.mac__tool { height: <52>; flex: none; display: flex; align-items: center; gap: <14>; padding: 0 <18>; border-bottom: <1> solid #e5e5ea; font-size: <13>; color: #1d1d1f; }
.mac__scheme { padding: <4> <10>; border-radius: <7>; background: #f2f2f7; color: #3c3c43; font-size: <12>; } .mac__scheme s { text-decoration: none; color: #aeaeb2; }
.mac__status { margin-left: auto; padding: <5> <12>; border-radius: <7>; background: #f2f2f7; color: #6e6e73; font-size: <12>; }
.mac__tabs { height: <30>; flex: none; display: flex; background: #f5f5f7; border-bottom: <1> solid #e5e5ea; font-size: <12>; color: #6e6e73; }
.mac__tabs span { display: flex; align-items: center; gap: <6>; padding: 0 <16>; border-right: <1> solid #e5e5ea; }
.mac__tabs span.on { background: #fff; color: #1d1d1f; }
.mac__tabs svg { width: <11>; height: <13>; }
.mac__code { list-style: none; margin: 0; padding: <10> 0; font: <12.5>/<19> "SF Mono", ui-monospace, Menlo, monospace; color: #1d1d1f; overflow: hidden; }
.mac__code li { display: flex; white-space: pre; }
.mac__code li.cur { background: #eef5ff; }
.mac__code i { width: <46>; flex: none; padding-right: <14>; text-align: right; font-style: normal; color: #aeaeb2; }
.mac__code .k { color: #9b2393; font-weight: 600; } .mac__code .d { color: #0f68a0; } .mac__code .t { color: #3900a0; } .mac__code .p { color: #1c464a; }
.mac__code .c { color: #5d6c79; } .mac__code .mk { color: #5d6c79; font-weight: 700; } .mac__code .s { color: #c41a16; } .mac__code .n { color: #1c00cf; }

/* ---------- macOS alert (Big Sur and later) ---------- */
.nsalert { width: <272>; padding: <20> <16> <16>; border-radius: <14>; background: rgba(246, 246, 248, 0.97); text-align: center; color: #1d1d1f;
  font-family: -apple-system, "SF Pro Text", "Inter", system-ui, sans-serif; letter-spacing: 0; display: flex; flex-direction: column; align-items: center;
  box-shadow: 0 <20> <50> rgba(0, 0, 0, 0.3), 0 0 0 <0.5> rgba(0, 0, 0, 0.18); }
.mac .nsalert { position: absolute; left: 50%; top: <52>; translate: -50% 0; }
.nsalert__icon { width: <64>; height: <64>; margin-bottom: <12>; }
.nsalert b { font-size: <13>; line-height: 1.3; font-weight: 700; }
.nsalert p { margin: <8> 0 <16>; font-size: <11>; line-height: 1.35; color: #3c3c43; }
.nsalert__btns { width: 100%; display: flex; flex-direction: column; gap: <8>; }
.nsalert__btns i { height: <28>; display: grid; place-items: center; border-radius: <7>; font-style: normal; font-size: <13>; background: rgba(0, 0, 0, 0.06); box-shadow: inset 0 0 0 <0.5> rgba(0, 0, 0, 0.08); }
.nsalert__btns i.def { background: linear-gradient(#2f90ff, #0a78f5); color: #fff; box-shadow: none; }
.macpane { container-type: inline-size; width: 100%; display: flex; justify-content: center; }
.macpane .nsalert { position: static; translate: none; }
"""

def mac_css():
    return re.sub(r'<(-?\d+(?:\.\d+)?)>', lambda m: f'calc({m.group(1)} * var(--mp))', CSS)
