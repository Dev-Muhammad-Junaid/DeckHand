/* Pixel Hand redesign board, round 2: the pixel identity.
   Glyphs on one 9 x 9 dot grid, 5 x 7 dot-matrix type, the status strip,
   phosphor focus, dissolve and scanline storyboards, and the key screens
   redone with them. Registers screens on window.PH.S before board.js renders. */
(function () {
  'use strict';
  var PH = window.PH;
  if (!PH) return;
  var S = PH.S, ic = PH.ic, app = PH.app, mac = PH.mac, chip = PH.chip, phone = PH.phone, sb = PH.sb, home = PH.home,
    pad = PH.pad, appDock = PH.appDock, hand = PH.hand, macpill = PH.macpill;

  /* ---------- Glyphs: 9 x 9 dots, 1-dot strokes, one lit accent (*) at most ---------- */
  var G = {
    pointer: ['#........', '##.......', '#.#......', '#..#.....', '#...#....', '#....#...', '#.####...', '##.......', '#........'],
    click: ['....#....', '.........', '..#####..', '..#...#..', '#.#.*.#.#', '..#...#..', '..#####..', '.........', '....#....'],
    screen: ['.........', '#########', '#.......#', '#.......#', '#.......#', '#.......#', '#########', '....#....', '..#####..'],
    deck: ['.........', '.###.###.', '.#.#.#.#.', '.###.###.', '.........', '.###.###.', '.#.#.#*#.', '.###.###.', '.........'],
    keyboard: ['.........', '#########', '#.......#', '#.#.#.#.#', '#.......#', '#.#####.#', '#.......#', '#########', '.........'],
    capture: ['##.....##', '#.......#', '.........', '...###...', '...#*#...', '...###...', '.........', '#.......#', '##.....##'],
    mission: ['.........', '###...###', '#.#...#.#', '###...###', '.........', '..#####..', '..#...#..', '..#####..', '.........'],
    desktop: ['.........', '#########', '#.......#', '##.....##', '##.....##', '#.......#', '#########', '....#....', '..#####..'],
    play: ['..#......', '..##.....', '..###....', '..####...', '..#####..', '..####...', '..###....', '..##.....', '..#......'],
    pause: ['.........', '.##...##.', '.##...##.', '.##...##.', '.##...##.', '.##...##.', '.##...##.', '.##...##.', '.........'],
    build: ['.######..', '.#.....#.', '.######..', '....#....', '....#....', '....#....', '....#....', '....#....', '....*....'],
    run: ['.#.......', '.##......', '.#.#.....', '.#..#....', '.#...*...', '.#..#....', '.#.#.....', '.##......', '.#.......'],
    stop: ['.........', '.#######.', '.#.....#.', '.#.....#.', '.#.....#.', '.#.....#.', '.#.....#.', '.#######.', '.........'],
    test: ['.........', '.........', '........#', '.......#.', '#.....#..', '.#...#...', '..#.#....', '...*.....', '.........'],
    search: ['..###....', '.#...#...', '#.....#..', '#.....#..', '#.....#..', '.#...#...', '..###.#..', '.......#.', '........*'],
    terminal: ['.........', '#########', '#.......#', '#.#.....#', '#..#....#', '#.#.##*.#', '#.......#', '#########', '.........'],
    lock: ['...###...', '..#...#..', '..#...#..', '.#######.', '.#.....#.', '.#..*..#.', '.#..#..#.', '.#.....#.', '.#######.'],
    send: ['....*....', '...#.#...', '..#.#.#..', '.#..#..#.', '....#....', '....#....', '....#....', '....#....', '....#....'],
    share: ['....*....', '...###...', '..#.#.#..', '....#....', '#...#...#', '#.......#', '#.......#', '#########', '.........'],
    ask: ['.........', '.#..#..#.', '.........', '.........', '.#..*..#.', '.........', '.........', '.#..#..#.', '.........'],
    laptop: ['.........', '.#######.', '.#.....#.', '.#.....#.', '.#.....#.', '.#######.', '#########', '.........', '.........'],
    iphone: ['..#####..', '..#...#..', '..#...#..', '..#...#..', '..#...#..', '..#...#..', '..#.*.#..', '..#####..', '.........'],
    arrowL: ['.........', '.........', '...#.....', '..#......', '.#######.', '..#......', '...#.....', '.........', '.........'],
    arrowR: ['.........', '.........', '.....#...', '......#..', '.#######.', '......#..', '.....#...', '.........', '.........'],
    displays: ['.........', '#####....', '#...#....', '#...#####', '#####...#', '....#...#', '....#.*.#', '....#####', '.........'],
    wired: ['...#.#...', '...#.#...', '..#####..', '..#...#..', '..#...#..', '...###...', '....#....', '....#....', '....*....'],
    vpn: ['.#######.', '.#.....#.', '.#.....#.', '.#..*..#.', '.#.....#.', '..#...#..', '...#.#...', '....#....', '.........'],
    audio: ['.........', '...#.....', '..##..#..', '###.#..#.', '#...#..*.', '###.#..#.', '..##..#..', '...#.....', '.........'],
    mute: ['.........', '...#.....', '..##.....', '###.#.#.#', '#...#..#.', '###.#.#.#', '..##.....', '...#.....', '.........'],
    paste: ['..#####..', '.##...##.', '.#.....#.', '.#.###.#.', '.#.....#.', '.#.###.#.', '.#.....#.', '.#######.', '.........'],
    type: ['#########', '....#....', '....#....', '....#....', '....#....', '....#....', '....#....', '....#....', '...#*#...'],
    region: ['#.#.#.#.#', '.........', '#.......#', '.........', '#...*...#', '.........', '#.......#', '.........', '#.#.#.#.#'],
    ocr: ['##.....##', '#.......#', '..#####..', '.........', '..####...', '.........', '..#####..', '#.......#', '##.....##'],
    pin: ['..#####..', '..#...#..', '..#...#..', '.#######.', '....#....', '....#....', '....#....', '....*....', '.........'],
    close: ['.........', '.#.....#.', '..#...#..', '...#.#...', '....#....', '...#.#...', '..#...#..', '.#.....#.', '.........'],
    plus: ['....#....', '....#....', '....#....', '....#....', '####*####', '....#....', '....#....', '....#....', '....#....'],
    pip: ['.........', '#########', '#.......#', '#.......#', '#...#####', '#...#...#', '#...#.*.#', '#########', '.........'],
    wifi: ['.........', '..#####..', '.#.....#.', '#.......#', '...###...', '..#...#..', '.........', '....*....', '.........'],
    settings: ['.........', '.....#...', '####.#.##', '.....#...', '.........', '..#......', '##.#.####', '..#......', '.........'],
    power: ['....*....', '.#..#..#.', '#...#...#', '#.......#', '#.......#', '#.......#', '.#.....#.', '..#####..', '.........']
  };
  var GLYPH_LABEL = { pointer: 'Pointer', click: 'Click', screen: 'Screen', deck: 'Deck', keyboard: 'Keyboard', capture: 'Capture', mission: 'Mission Control', desktop: 'Show Desktop', play: 'Play', pause: 'Pause', build: 'Build', run: 'Run', stop: 'Stop', test: 'Test', search: 'Find', terminal: 'Console', lock: 'Lock', send: 'Send', share: 'Share', ask: 'Ask', laptop: 'Mac', iphone: 'iPhone', arrowL: 'Space left', arrowR: 'Space right', displays: 'Displays', wired: 'Wired', vpn: 'VPN', audio: 'Sound on', mute: 'Sound off', paste: 'Paste', type: 'Type', region: 'Region', ocr: 'Read text', pin: 'Pin', close: 'Close', plus: 'Add', pip: 'Picture in Picture', wifi: 'Wi-Fi', settings: 'Settings', power: 'Wake' };

  /* One dot = 78 % of the pitch, corner radius 30 % of the dot. */
  function glyph(name, p, opt) {
    opt = opt || {};
    var rows = G[name]; if (!rows) return '';
    var d = p * 0.78, r = d * 0.3, o = (p - d) / 2, out = '';
    for (var y = 0; y < 9; y++) for (var x = 0; x < 9; x++) {
      var c = rows[y][x];
      if (c === '#' || c === '*') out += '<rect x="' + (x * p + o).toFixed(2) + '" y="' + (y * p + o).toFixed(2) + '" width="' + d.toFixed(2) + '" height="' + d.toFixed(2) + '" rx="' + r.toFixed(2) + '"' + (c === '*' && !opt.flat ? ' class="a"' : '') + '/>';
      else if (opt.off) out += '<rect class="o" x="' + (x * p + o).toFixed(2) + '" y="' + (y * p + o).toFixed(2) + '" width="' + d.toFixed(2) + '" height="' + d.toFixed(2) + '" rx="' + r.toFixed(2) + '"/>';
    }
    return '<svg class="pg' + (opt.cls ? ' ' + opt.cls : '') + '" width="' + 9 * p + '" height="' + 9 * p + '" viewBox="0 0 ' + 9 * p + ' ' + 9 * p + '" aria-hidden="true">' + out + '</svg>';
  }

  /* ---------- 5 x 7 dot-matrix type ---------- */
  var F = {
    '0': '01110100011001110101110011000101110', '1': '00100011000010000100001000010001110', '2': '01110100010000100010001000100011111', '3': '11110000010000101110000010000111110',
    '4': '00010001100101010010111110001000010', '5': '11111100001111000001000011000101110', '6': '00110010001000011110100011000101110', '7': '11111000010001000100010000100001000',
    '8': '01110100011000101110100011000101110', '9': '01110100011000101111000010001001100',
    A: '01110100011000111111100011000110001', B: '11110100011000111110100011000111110', C: '01110100011000010000100001000101110', D: '11110100011000110001100011000111110',
    E: '11111100001000011110100001000011111', F: '11111100001000011110100001000010000', G: '01110100011000010111100011000101111', H: '10001100011000111111100011000110001',
    I: '01110001000010000100001000010001110', J: '00111000100001000010000101001001100', K: '10001100101010011000101001001010001', L: '10000100001000010000100001000011111',
    M: '10001110111010110101100011000110001', N: '10001100011100110101100111000110001', O: '01110100011000110001100011000101110', P: '11110100011000111110100001000010000',
    Q: '01110100011000110001101011001001101', R: '11110100011000111110101001001010001', S: '01111100001000001110000010000111110', T: '11111001000010000100001000010000100',
    U: '10001100011000110001100011000101110', V: '10001100011000110001100010101000100', W: '10001100011000110101101011010101010', X: '10001100010101000100010101000110001',
    Y: '10001100010101000100001000010000100', Z: '11111000010001000100010001000011111',
    ' ': '00000000000000000000000000000000000', '·': '00000000000000000100000000000000000', ':': '00000001000000000000000000010000000', '/': '00001000100001000100010000100010000',
    '%': '11001110100001000100010000101110011', '-': '00000000000000001110000000000000000', '.': '00000000000000000000000000000000100', '+': '00000001000010011111001000010000000', '<': '00010001000100010000010000010000010', '>': '01000001000001000001000100010001000'
  };
  function dmText(str, p, opt) {
    opt = opt || {};
    str = String(str).toUpperCase();
    var d = p * 0.8, r = d * 0.32, o = (p - d) / 2, out = '', w = Math.max(1, str.length * 6 - 1);
    for (var i = 0; i < str.length; i++) {
      var bits = F[str[i]] || F[' '];
      for (var b = 0; b < 35; b++) {
        var x = i * 6 + (b % 5), y = Math.floor(b / 5);
        if (bits[b] === '1') out += '<rect x="' + (x * p + o).toFixed(2) + '" y="' + (y * p + o).toFixed(2) + '" width="' + d.toFixed(2) + '" height="' + d.toFixed(2) + '" rx="' + r.toFixed(2) + '"/>';
        else if (opt.off) out += '<rect class="o" x="' + (x * p + o).toFixed(2) + '" y="' + (y * p + o).toFixed(2) + '" width="' + d.toFixed(2) + '" height="' + d.toFixed(2) + '" rx="' + r.toFixed(2) + '"/>';
      }
    }
    return '<svg class="dmt' + (opt.cls ? ' ' + opt.cls : '') + '" width="' + (w * p).toFixed(1) + '" height="' + 7 * p + '" viewBox="0 0 ' + (w * p).toFixed(1) + ' ' + 7 * p + '" role="img" aria-label="' + (opt.label || str) + '">' + out + '</svg>';
  }

  /* ---------- Shared round-2 parts ---------- */
  function strip(items, opt) {
    opt = opt || {};
    return '<div class="sstrip' + (opt.cls ? ' ' + opt.cls : '') + '" style="' + (opt.style || '') + '"><i class="sstrip__px' + (opt.off ? ' off' : '') + '"></i>' + dmText(items.join(' · '), opt.p || 2, { cls: 'dmt--glow', label: items.join(', ') }) + '</div>';
  }
  function badge(kind) {
    var m = { wired: ['wired', 'WIRED', 'lb--mint'], vpn: ['vpn', 'VPN', 'lb--sky'], wifi: ['wifi', 'WI-FI', 'lb--mute'], direct: ['wifi', 'DIRECT', 'lb--mute'] }[kind];
    return '<span class="lb ' + m[2] + '">' + glyph(m[0], 1.4, { flat: 1 }) + dmText(m[1], 1.4) + '</span>';
  }
  function deskDots(n, cur, full) {
    var h = '<span class="ddots" role="img" aria-label="Desktop ' + (cur + 1) + ' of ' + n + '">';
    for (var i = 0; i < n; i++) h += '<i class="' + (i === cur ? 'on' : '') + (full && full.indexOf(i) >= 0 ? ' fs' : '') + '"></i>';
    return h + '</span>';
  }
  function gchip(g, l, k, st, cls) {
    return '<span class="chip gch ' + (st ? 'chip--' + st : '') + ' ' + (cls || '') + '"><span class="chip__l">' + (g ? glyph(g, 2, { cls: 'gch__g' }) : '') + l + (k ? '<kbd>' + k + '</kbd>' : '') + '</span><span class="chip__dots"><i></i><i></i><i></i></span></span>';
  }
  function gkey(g, l, k, st, opt) {
    opt = opt || {};
    return '<span class="key gkey' + (st ? ' key--' + st : '') + (opt.navy ? ' key--navy' : '') + (opt.ghost ? ' key--ghost' : '') + (opt.ask ? ' key--ask' : '') + (opt.focus ? ' phos' : '') + '"><span class="key__g">' + glyph(g, 3) + '</span><span class="key__l">' + l + '</span>' + (k ? '<span class="key__k">' + k + '</span>' : '') + '<span class="key__s"><i></i><i></i><i></i><i></i></span></span>';
  }
  function gdeck(keys, cols, gap) {
    return '<div class="deck" style="grid-template-columns:repeat(' + cols + ',minmax(0,1fr));gap:' + (gap || 12) + 'px">' + keys.map(function (k) { return gkey.apply(null, k); }).join('') + '</div>';
  }
  var XKEYS = [['build', 'Build', '⌘B', 'ok'], ['run', 'Run', '⌘R', 'send'], ['stop', 'Stop', '⌘.'], ['test', 'Test', '⌘U'], ['search', 'Open Quickly', '⇧⌘O'], ['terminal', 'Console', '⇧⌘C'], ['region', 'Canvas', '⌥⌘↩'], ['close', 'Clean Build', '⇧⌘K', null, { ask: 1 }], ['mission', 'Mission Control', '', null, { navy: 1 }], ['desktop', 'Show Desktop', '', null, { navy: 1 }], ['arrowL', 'Space Left', '⌃←'], ['arrowR', 'Space Right', '⌃→']];
  function tabs(sel) {
    var t = [['pointer', 'Pointer'], ['screen', 'Screen'], ['deck', 'Deck']];
    return '<div class="sdock" style="padding:8px 16px 0"><div class="tabs glass">' + t.map(function (x) { return '<span class="' + (x[0] === sel ? 'on' : '') + '">' + glyph(x[0], 2.6) + x[1] + (x[0] === sel ? '<i class="tabdot"></i>' : '') + '</span>'; }).join('') + '</div><span class="ask glass">' + glyph('ask', 2.6) + '</span></div>';
  }
  function hdr2(o) {
    o = o || {};
    return '<div class="hdr hdr2">' + macpill({ sub: o.sub || 'Xcode', off: o.off, name: o.name }) + (o.badge ? badge(o.badge) : '') + '<span class="grow"></span>' + (o.trailing || ['capture', 'settings']).map(function (n) { return '<span class="circ glass">' + glyph(n, 2.2) + '</span>'; }).join('') + '</div>';
  }
  function adock2(o) { return appDock(Object.assign({ style: 'margin:0 16px;height:56px;border-radius:28px' }, o || {})).replace(ic('keyboard'), glyph('keyboard', 2.2)); }
  function pg(n, cur) { return '<span class="pgc">' + dmText((cur < 10 ? '0' : '') + cur + '/' + (n < 10 ? '0' : '') + n, 1.6, { label: 'Page ' + cur + ' of ' + n }) + '</span>'; }
  function grid(c, m, g) { return '<div class="gridov" style="--c:' + c + ';--m:' + m + 'px;--g:' + g + 'px"></div>'; }

  /* ---------- Component and identity sheets ---------- */
  S.glyphSheet = function (t) {
    var names = Object.keys(G), cells = '';
    names.forEach(function (n) { cells += '<div class="gs__c">' + glyph(n, 4, { off: 1 }) + '<span>' + GLYPH_LABEL[n] + '</span></div>'; });
    var sizes = '<div class="row" style="gap:24px;align-items:flex-end;padding:4px 2px 0">' + [[2, 'Chip · pitch 2 · 18 pt'], [3, 'Key · pitch 3 · 27 pt'], [4, 'Empty state · pitch 4 · 36 pt'], [6, 'Hero · pitch 6 · 54 pt']].map(function (s) { return '<div style="display:flex;flex-direction:column;gap:8px;align-items:flex-start">' + glyph('run', s[0]) + '<span class="cap">' + s[1] + '</span></div>'; }).join('') + '</div>';
    var inner = '<div class="sheetpad"><div class="lbl0">40 glyphs · 9 × 9 dot grid · 1-dot strokes · at most one lit accent dot (the action point)</div><div class="gs">' + cells + '</div><div class="lbl0" style="margin-top:20px">Four sizes, whole-point pitches only</div>' + sizes + '</div>';
    return { w: 720, h: 600, frame: 'bare', html: '<div class="ph v2 ' + t + '" style="width:720px;height:600px">' + inner + '</div>' };
  };

  S.typeSheet = function (t) {
    var navy = function (h) { return '<div class="navyplate">' + h + '</div>'; };
    var inner = '<div class="sheetpad" style="gap:18px">' +
      '<div class="lbl0">Dot-matrix type: 5 × 7 cells, 1-cell tracking. Display only: status, counters, codes. Always paired with real text for VoiceOver.</div>' +
      navy(dmText('ABCDEFGHIJKLMNOPQRSTUVWXYZ', 2.2, { off: 1, cls: 'dmt--glow' }) + dmText('0123456789 · : / % - + < >', 2.2, { off: 1, cls: 'dmt--glow' })) +
      '<div class="lbl0">Status strip (mirror, Mac cards, PiP-adjacent chrome): pitch 2, phosphor on navy, unlit cells hidden</div>' +
      strip(['STUDIO', 'DISPLAY 1/2', 'DESK 2/3', '60 FPS', '7 MS'], { style: 'width:100%' }) +
      strip(['MACBOOK AIR', 'PAGES', 'DIALOG WAITING'], { style: 'width:100%', cls: 'sstrip--warn' }) +
      strip(['MAC MINI', 'LOCKED'], { style: 'width:100%', off: 1, cls: 'sstrip--dim' }) +
      '<div class="lbl0">Counters and numerals</div>' +
      '<div class="row" style="gap:22px;flex-wrap:wrap">' + navy(dmText('01/03', 3, { cls: 'dmt--glow', label: 'Page 1 of 3' })) + navy(dmText('60 FPS', 3, { cls: 'dmt--glow' })) + navy(dmText('4.1/9.4 MB', 2, { cls: 'dmt--glow' })) + '<span class="pgc pgc--light">' + dmText('01/03', 1.6) + '</span></div>' +
      '<div class="lbl0">Link badges: dot-matrix label at pitch 1.4 in a 20 pt capsule</div>' +
      '<div class="row" style="gap:10px">' + badge('wired') + badge('vpn') + badge('wifi') + badge('direct') + '</div></div>';
    return { w: 720, h: 640, frame: 'bare', html: '<div class="ph v2 ' + t + '" style="width:720px;height:640px">' + inner + '</div>' };
  };

  S.stateSheet = function (t) {
    function waveRow(phase) {
      var h = '<div class="wave">';
      for (var y = 0; y < 3; y++) for (var x = 0; x < 9; x++) {
        var v = Math.max(0, Math.cos((x / 8 - phase) * Math.PI * 1.6));
        h += '<i style="opacity:' + (0.18 + 0.82 * Math.pow(v, 3)).toFixed(2) + ';box-shadow:0 0 ' + (6 * Math.pow(v, 3)).toFixed(1) + 'px rgba(61,224,224,' + (0.8 * Math.pow(v, 3)).toFixed(2) + ')"></i>';
      }
      return h + '</div>';
    }
    var inner = '<div class="sheetpad" style="gap:16px">' +
      '<div class="lbl0">Loading: a brightness wave crosses a 9 × 3 dot block, 1.2 s period (TimelineView). Reduce Motion: static middle frame.</div>' +
      '<div class="row" style="gap:18px">' + [0.1, 0.35, 0.6, 0.85].map(function (p) { return '<div class="navyplate" style="padding:14px">' + waveRow(p) + '</div>'; }).join('') + '</div>' +
      '<div class="lbl0">Empty states: the glyph at pitch 6 on an unlit grid, one dot breathing (2.4 s). Headline in display, one sentence, one action.</div>' +
      '<div class="grid2c">' +
      '<div class="empt"><div class="empt__art">' + glyph('deck', 6, { off: 1 }) + '</div><b>No keys for Figma yet</b><span>Add keys from Figma’s menus, or let Pixel Hand suggest some.</span><div class="row" style="gap:8px"><span class="pillbtn pillbtn--accent">Suggest keys</span><span class="pillbtn">Add a key</span></div></div>' +
      '<div class="empt"><div class="empt__art">' + glyph('displays', 6, { off: 1 }) + '</div><b>Looking for your Macs</b><span>Open Pixel Hand on your Mac. Both need the same Wi-Fi or a cable.</span><div class="beam">' + '<i class="on"></i><i class="on"></i><i class="on"></i><i></i><i></i><i></i><i></i><i></i>' + '</div></div></div>' +
      '<div class="lbl0">Phosphor focus and highlight</div>' +
      '<div class="row" style="gap:16px;align-items:center">' + gkey('run', 'Run', '⌘R', null, { focus: 1 }) + gkey('build', 'Build', '⌘B', 'ok') + gchip('build', 'Build', '⌘B', null, 'phos') + '<span class="cap" style="max-width:250px">Keyboard focus and the "you are here" item get a dotted phosphor ring 3 pt outside the shape, with a soft bloom. Pressing lights the glyph’s dots for 120 ms.</span></div></div>';
    return { w: 720, h: 700, frame: 'bare', html: '<div class="ph v2 ' + t + '" style="width:720px;height:700px">' + inner + '</div>' };
  };

  /* Transition storyboards, drawn frame by frame from the real rule. */
  function hash(i) { var x = Math.sin(i * 12.9898 + 4.1414) * 43758.5453; return x - Math.floor(x); }
  S.motionSheet = function (t) {
    /* Dissolve: each 8 pt cell has a fixed random threshold; cells whose
       threshold has passed show the new surface, the 12 % band just behind
       the edge burns as phosphor dots. Drawn with CSS masks per frame. */
    var fromHTML = '<div style="position:absolute;inset:0" class="padmini"></div>';
    var toHTML = '<div style="position:absolute;inset:0;background:var(--canvas)"><div style="display:grid;grid-template-columns:repeat(4,1fr);gap:5px;padding:10px">' + new Array(8).join('<i style="aspect-ratio:1;border-radius:6px;background:var(--raised);box-shadow:inset 0 0 0 .5px var(--hair)"></i>') + '<i style="aspect-ratio:1;border-radius:6px;background:var(--raised)"></i></div></div>';
    function frame(p) {
      var W = 160, H = 100, c = 8, cols = 20, rows = 13, keep = '', burn = '';
      for (var y = 0; y < rows; y++) for (var x = 0; x < cols; x++) {
        var h = hash(y * cols + x);
        if (h >= p) keep += '<rect x="' + x * c + '" y="' + y * c + '" width="' + c + '" height="' + c + '"/>';
        else if (h >= p - 0.12) burn += '<rect x="' + (x * c + 1.2) + '" y="' + (y * c + 1.2) + '" width="5.6" height="5.6" rx="1.6"/>';
      }
      var mask = "url('data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="160" height="104">' + keep + '</svg>') + "')";
      return '<div class="sbf"><div class="sbf__in">' + toHTML + '<div style="position:absolute;inset:0;-webkit-mask-image:' + mask + ';mask-image:' + mask + '">' + fromHTML + '</div><svg class="burn" width="160" height="104" style="position:absolute;inset:0">' + burn + '</svg></div><span class="cap">' + Math.round(p * 280) + ' ms</span></div>';
    }
    function scan(p) {
      var y = Math.round(p * 100);
      return '<div class="sbf"><div class="sbf__in" style="background:#000">' + '<div style="position:absolute;inset:0;clip-path:inset(0 0 ' + (100 - y) + 'px 0)">' + mac({ cur: [50, 45] }) + '</div>' +
        (p < 1 ? '<div style="position:absolute;left:0;right:0;top:' + Math.max(0, y - 14) + 'px;height:14px;background:linear-gradient(transparent,rgba(61,224,224,.45))"></div><div style="position:absolute;left:0;right:0;top:' + y + 'px;height:1.5px;background:#EFFFFC;box-shadow:0 0 8px #3DE0E0,0 0 2px #fff"></div>' : '') + '</div><span class="cap">' + Math.round(p * 360) + ' ms</span></div>';
    }
    function power(p) {
      var s = p < 0.35 ? p / 0.35 * 1.15 : 1.15 - (p - 0.35) / 0.65 * 0.15;
      var o = Math.min(1, p * 2.2);
      return '<div class="sbf"><div class="sbf__in brandmini" style="display:grid;place-items:center"><span style="opacity:' + o.toFixed(2) + ';filter:brightness(' + s.toFixed(2) + ')">' + hand(Math.round(44 + 8 * Math.min(1, p * 1.5))) + '</span></div><span class="cap">' + Math.round(p * 600) + ' ms</span></div>';
    }
    var inner = '<div class="sheetpad" style="gap:12px">' +
      '<div class="lbl0">Pixel dissolve · switching surface or Mac · 280 ms, 8 pt cells (6 pt on compact), seeded per transition, 12 % phosphor edge band · Reduce Motion: 160 ms cross-fade</div>' +
      '<div class="sb-row">' + [0, 0.25, 0.5, 0.75, 1].map(frame).join('') + '</div>' +
      '<div class="lbl0">Scanline · mirror connects, display changes, PiP returns · 360 ms ease-out, 1.5 pt phosphor line, 14 pt cyan afterglow · Reduce Motion: 160 ms fade</div>' +
      '<div class="sb-row">' + [0, 0.3, 0.6, 0.85, 1].map(scan).join('') + '</div>' +
      '<div class="lbl0">Power-on · launch, pairing success, Pro unlocked · 600 ms; dots light in a 0–180 ms jitter, overshoot to 115 % brightness at 210 ms, settle by 600 ms (the website hero curve)</div>' +
      '<div class="sb-row">' + [0.1, 0.3, 0.5, 0.75, 1].map(power).join('') + '</div></div>';
    return { w: 960, h: 520, frame: 'bare', html: '<div class="ph v2 ' + t + '" style="width:960px;height:520px">' + inner + '</div>' };
  };

  S.brandSheet = function () {
    function menubar(state, label) {
      var cls = { idle: 'mb--idle', ready: '', request: 'mb--req', active: 'mb--act', send: 'mb--send' }[state];
      return '<div class="mbcell"><div class="mbbar"><span class="mbicon ' + cls + '">' + hand(20) + '</span></div><span class="cap" style="color:rgba(255,255,255,.7)">' + label + '</span></div>';
    }
    var inner = '<div class="sheetpad" style="gap:16px;color:#fff">' +
      '<div class="lbl0" style="color:rgba(255,255,255,.7)">Menu-bar dot hand (18 pt template): one image, five states</div>' +
      '<div class="row" style="gap:14px;flex-wrap:wrap">' + menubar('idle', 'Not ready (50 %)') + menubar('ready', 'Ready') + menubar('request', 'Device asking · fingertip blinks 1 Hz') + menubar('active', 'Being controlled · rays lit') + menubar('send', 'Receiving · beam under') + '</div>' +
      '<div class="lbl0" style="color:rgba(255,255,255,.7)">The icon carries through: launch screen = the icon’s screen, so opening the app zooms into the same dots</div>' +
      '<div class="row" style="gap:18px;align-items:center;flex-wrap:wrap">' +
      '<div class="icon"><div class="icon__scr">' + hand(40) + '<i class="icon__mint"></i></div></div>' +
      '<span style="font:600 22px/1 var(--f-ui);color:rgba(255,255,255,.4)">→</span>' +
      '<div class="launch">' + '<div class="icon__scr" style="inset:0;border-radius:0">' + hand(66) + '<i class="icon__mint" style="right:22px;top:22px"></i></div></div>' +
      '<span style="font:600 22px/1 var(--f-ui);color:rgba(255,255,255,.4)">→</span>' +
      '<div class="launch" style="background:var(--screen)"><div class="padmini" style="position:absolute;inset:10px 6px 44px;border-radius:14px"></div><div style="position:absolute;left:6px;right:6px;bottom:8px;height:28px;border-radius:14px;background:rgba(40,48,100,.8)"></div></div>' +
      '<span class="cap" style="color:rgba(255,255,255,.7);max-width:220px">Icon tile → launch screen (navy, hand at the icon’s position, mint pixel top-right) → the trackpad’s dot grid. One continuous zoom (hero motion).</span></div>' +
      '<div class="lbl0" style="color:rgba(255,255,255,.7)">Widgets and Control Center use the same dots</div>' +
      '<div class="row" style="gap:14px">' +
      '<div class="wdg">' + strip(['STUDIO', 'XCODE'], { style: 'width:100%' }) + '<div class="row" style="gap:8px;margin-top:10px">' + ['build', 'run', 'lock', 'capture'].map(function (g) { return '<span class="wdg__k">' + glyph(g, 2.6) + '</span>'; }).join('') + '</div></div>' +
      '<div class="wdg" style="width:150px;display:grid;place-items:center;gap:6px">' + glyph('lock', 5) + dmText('LOCK STUDIO', 1.6, { cls: 'dmt--glow' }) + '</div>' +
      '<div class="ccb">' + glyph('play', 2.8) + '</div><div class="ccb">' + glyph('lock', 2.8) + '</div></div></div>';
    return { w: 960, h: 520, frame: 'bare', html: '<div class="ph v2 dark brandbg" style="width:960px;height:520px">' + inner + '</div>' };
  };

  S.components2 = function (t) {
    var inner = '<div class="sheetpad" style="gap:14px">' +
      '<div class="lbl0">Chips with glyphs · idle · sending · delivered · refused · dialog default · AI</div>' +
      '<div class="row" style="gap:8px;flex-wrap:wrap">' + gchip('build', 'Build', '⌘B') + gchip('run', 'Run', '⌘R', 'send') + gchip('test', 'Test', '⌘U', 'ok') + gchip('close', 'Quit', '⌘Q', 'no') + gchip('', 'Save', '↩', '', 'chip--def') + '<span class="chip chip--ai gch"><span class="chip__l">' + glyph('ask', 2) + 'Suggest</span></span></div>' +
      '<div class="lbl0">Keys with glyphs</div>' +
      gdeck([['build', 'Build', '⌘B', 'ok'], ['run', 'Run', '⌘R', 'send'], ['close', 'Clean', '⇧⌘K', null, { ask: 1 }], ['mission', 'Mission', '', null, { navy: 1 }], ['ocr', 'Read Text', '', null, { ghost: 1 }], ['run', 'Focused', '⌘R', null, { focus: 1 }]], 6, 12) +
      '<div class="lbl0">Mirror toolbar · display picker · desktop dots · cursor badge · audio</div>' +
      '<div class="navyplate" style="display:flex;gap:12px;align-items:center;padding:12px">' +
      '<div class="mtool glass on-navy"><span class="on">' + glyph('click', 2) + 'Direct</span><span>' + glyph('displays', 2) + dmText('1/2', 1.6) + '</span><span>' + glyph('arrowL', 2) + '</span>' + deskDots(3, 1, [2]) + '<span>' + glyph('arrowR', 2) + '</span><span class="on">' + glyph('audio', 2) + '</span><span>' + glyph('pip', 2) + '</span></div>' +
      '<span class="curbadge">' + glyph('pointer', 1.6) + dmText('ON 2', 1.4) + glyph('arrowR', 1.6) + '</span></div>' +
      '<div class="lbl0">Header: Mac pill + link badge · status pill · toast</div>' +
      '<div class="row" style="gap:10px;flex-wrap:wrap;align-items:center">' + macpill({}) + badge('wired') + badge('vpn') + '<span class="toast glass"><i></i>Build delivered to Studio</span></div>' +
      '<div class="spill spill--warn">' + glyph('lock', 2) + '<span><b>Studio is locked.</b> Type the password to unlock.</span><span class="spill__fix">Keyboard</span></div></div>';
    return { w: 720, h: 640, frame: 'bare', html: '<div class="ph v2 ' + t + '" style="width:720px;height:640px">' + inner + '</div>' };
  };

  /* ---------- Key screens, round 2 ---------- */
  function mirrorTile(style, opt) {
    opt = opt || {};
    return '<div class="mir mir2" style="position:absolute;' + style + '">' + mac({ cur: [44, 40], dlg: opt.dlg }) + '<div class="mir2__top">' + strip(opt.items || ['LIVE', 'D1', '60'], { p: 1.4, style: 'height:18px;padding:0 6px;gap:5px' }) + '</div></div>';
  }

  S.v2Pointer = function (t) {
    var inner = '<div class="col">' + sb('pro') + hdr2({ badge: 'wired' }) +
      pad({ style: 'margin:0 16px', mirror: null, clicks: true, lit: [[150, 290, 70, 1], [110, 330, 40, 0.5]], cap: false,
        extra: mirrorTile('right:12px;top:12px;width:176px;height:110px') + '<div class="pad__cap2" style="top:auto;bottom:64px">' + glyph('click', 1.6) + dmText('2 FINGERS · SCROLL', 1.3) + '</div>' }) +
      '<div class="strip fade-r" style="padding:8px 16px">' + gchip('', 'Save', '↩', '', 'chip--def') + gchip('', 'Cancel', 'esc', '', 'chip--dlg') + gchip('', 'Don’t Save', '⌘⌫', '', 'chip--dlg') + '</div>' +
      adock2() + tabs('pointer') + home('pro') + grid(4, 16, 12) + '</div>';
    return phone(402, 874, t + ' v2', inner);
  };

  S.v2Screen = function (t) {
    var inner = '<div class="col">' + sb('pro') + hdr2({ badge: 'vpn' }) +
      '<div class="mirbox">' +
      '<div style="position:absolute;left:-40%;top:-30%;width:200%;height:200%">' + mac({ dlg: true, cur: [47, 33] }) + '</div>' +
      '<div style="position:absolute;left:8px;right:8px;top:8px;display:flex;gap:8px;align-items:center">' + strip(['STUDIO', 'D1/2', 'DESK 2/3', '60 FPS'], { p: 1.6, style: 'height:20px;gap:6px' }) + '<span class="grow"></span><span class="curbadge">' + glyph('pointer', 1.6) + dmText('ON 2', 1.4) + glyph('arrowR', 1.6) + '</span></div>' +
      '<div class="minimap">' + mac({ dlg: true }) + '<span></span></div>' +
      '<div class="mtool glass on-navy" style="position:absolute;left:50%;bottom:8px;translate:-50% 0"><span class="on">' + glyph('click', 2) + '</span><span>' + glyph('displays', 2) + dmText('1/2', 1.6) + '</span><span>' + glyph('arrowL', 2) + '</span>' + deskDots(3, 1, [2]) + '<span>' + glyph('arrowR', 2) + '</span><span class="on">' + glyph('audio', 2) + '</span><span>' + glyph('pip', 2) + '</span></div>' +
      '</div>' +
      pad({ style: 'margin:12px 16px 0', cap: false, lit: [[220, 110, 50, 0.8]], extra: '<div class="pad__cap2">' + glyph('pointer', 1.6) + dmText('TRACKPAD · FOLLOWS CURSOR', 1.3) + '</div>' }) +
      '<div class="strip fade-r" style="padding:8px 16px">' + gchip('', 'Save', '↩', '', 'chip--def') + gchip('', 'Cancel', 'esc', '', 'chip--dlg') + gchip('', 'Don’t Save', '⌘⌫', '', 'chip--dlg') + '</div>' +
      adock2() + tabs('screen') + home('pro') + grid(4, 16, 12) + '</div>';
    return phone(402, 874, t + ' v2', inner);
  };

  S.v2Displays = function (t) {
    var base = S.v2Screen(t).html.replace(/^<div class="ph [^"]*" style="[^"]*">/, '').replace(/<\/div>$/, '');
    function disp(w, h, name, sub, n, cur, full, sel, cursor) {
      return '<div class="dispc' + (sel ? ' sel' : '') + '" style="width:' + w + 'px"><div class="dispc__scr" style="height:' + h + 'px">' + mac({}) + (cursor ? '<span class="dispc__cur">' + glyph('pointer', 1.6, { cls: 'pg--ph' }) + '</span>' : '') + '</div><div class="row" style="gap:8px;justify-content:space-between"><span><b>' + name + '</b><small>' + sub + '</small></span>' + deskDots(n, cur, full) + '</div></div>';
    }
    var sheet = '<div class="scrim"></div><div class="sheet-ui" style="height:470px"><div class="grab"></div><div class="sheet-ui__h"><h6>Show which display?</h6><span class="circ glass" style="width:36px;height:36px">' + glyph('close', 1.8) + '</span></div>' +
      '<div class="lbl" style="padding:2px 20px 12px">Arranged as on Studio. The cursor is on Display 2.</div>' +
      '<div class="row" style="gap:12px;padding:0 16px;align-items:flex-end">' + disp(196, 122, 'Built-in', 'Display 1 · 3 desktops', 3, 1, [2], 1, 0) + disp(158, 89, 'HP 24', 'Display 2 · 1 desktop', 1, 0, null, 0, 1) + '</div>' +
      '<div class="list" style="margin-top:16px"><div class="li"><span class="li__t">Follow the cursor<small>Switch the picture when the pointer moves to another display</small></span><span class="tog on"></span></div><div class="li"><span class="li__t">Desktop 3 is Keynote in full screen</span>' + deskDots(3, 1, [2]) + '</div></div></div>';
    return phone(402, 874, t + ' v2', base + sheet);
  };

  S.v2Deck = function (t) {
    var inner = '<div class="col">' + sb('pro') + hdr2({}) +
      '<div class="grow" style="display:flex;flex-direction:column;gap:12px;padding-top:4px">' +
      '<div class="row" style="gap:12px;padding:0 16px">' + app('xcode', 'sm') + '<div style="display:flex;flex-direction:column;gap:4px;flex:1;min-width:0"><b style="font:500 22px/1 var(--f-disp);letter-spacing:-.5px">Xcode</b><span class="row" style="gap:6px;color:var(--ink2);font:500 12px/1 var(--f-ui)">' + glyph('pin', 1.4) + 'Follows the front app</span></div>' + pg(3, 1) + '<span class="pillbtn" style="height:36px">Edit</span></div>' +
      '<div style="padding:0 16px">' + gdeck(XKEYS, 4, 12) + '</div>' +
      '<div class="sugg">' + '<div class="row" style="gap:8px">' + glyph('ask', 2, { cls: 'pg--acc' }) + '<b style="font:600 14px/1.2 var(--f-ui);color:var(--accent-ink);flex:1">3 keys from Xcode’s menus</b><span class="pillbtn pillbtn--accent" style="height:32px">Keep all</span></div>' +
      gdeck([['screen', 'Minimap', '⌃⇧⌘M', null, { ghost: 1 }], ['settings', 'Scheme…', '⌘<', null, { ghost: 1 }], ['region', 'Preview', '⌥⌘P', null, { ghost: 1 }], ['plus', 'Edit page', '', null, { ghost: 1 }]], 4, 12) + '</div></div>' +
      '<div class="strip fade-r" style="padding:8px 16px">' + gchip('build', 'Build', '⌘B', 'ok') + gchip('run', 'Run', '⌘R', 'send') + gchip('stop', 'Stop', '⌘.') + gchip('search', 'Open Quickly', '⇧⌘O') + '</div>' +
      adock2() + tabs('deck') + home('pro') + grid(4, 16, 12) + '</div>';
    return phone(402, 874, t + ' v2', inner);
  };

  S.v2DeckAX = function (t) {
    function row(g, l, k) { return '<div class="axrow">' + glyph(g, 3) + '<span>' + l + '</span><kbd>' + k + '</kbd></div>'; }
    var inner = '<div class="col">' + sb('pro') + '<div class="hdr hdr2">' + macpill({ sub: ' ' }).replace('<span> </span>', '') + '<span class="grow"></span><span class="circ glass">' + glyph('settings', 2.2) + '</span></div>' +
      '<div class="row" style="gap:12px;padding:4px 16px 12px"><b style="font:500 34px/1.05 var(--f-disp);letter-spacing:-.8px;flex:1">Xcode</b>' + pg(3, 1) + '</div>' +
      '<div class="grow" style="display:flex;flex-direction:column;gap:12px;padding:0 16px">' + row('build', 'Build', '⌘B') + row('run', 'Run', '⌘R') + row('stop', 'Stop', '⌘.') + row('test', 'Test', '⌘U') + row('search', 'Open Quickly', '⇧⌘O') + '</div>' +
      '<div class="sdock" style="padding:8px 16px 0"><div class="tabs glass">' + ['pointer', 'screen', 'deck'].map(function (n) { return '<span class="' + (n === 'deck' ? 'on' : '') + '">' + glyph(n, 3) + '</span>'; }).join('') + '</div><span class="ask glass">' + glyph('ask', 3) + '</span></div>' + home('pro') + '</div>';
    return phone(402, 874, t + ' v2 ax', inner);
  };

  S.v2Macs = function (t) {
    var base = S.v2Pointer(t).html.replace(/^<div class="ph [^"]*" style="[^"]*">/, '').replace(/<\/div>$/, '');
    function card(name, items, bd, opt) {
      opt = opt || {};
      return '<div class="mcard mcard2' + (opt.focus ? ' focus' : '') + '"><div class="mcard__shot' + (opt.off ? ' off' : '') + '">' + mac({ dlg: opt.dlg, cur: [40, 50] }) + '<div class="mcard2__strip">' + strip(items, { p: 1.3, style: 'height:16px;padding:0 5px;gap:4px;border-radius:6px', cls: opt.warn ? 'sstrip--warn' : opt.off ? 'sstrip--dim' : '', off: opt.off }) + '</div></div>' +
        '<div class="mcard__meta"><span style="flex:1;min-width:0"><b>' + name + '</b></span>' + (bd ? badge(bd) : '') + '</div>' + (opt.desks ? '<div class="row" style="gap:6px;padding:0 3px 2px">' + deskDots.apply(null, opt.desks) + '</div>' : '') + '</div>';
    }
    var sheet = '<div class="scrim"></div><div class="sheet-ui" style="height:612px"><div class="grab"></div>' +
      '<div class="sheet-ui__h"><h6>My Macs</h6><span class="pillbtn" style="height:36px">' + glyph('plus', 1.6) + 'Add</span></div>' +
      '<div style="padding:8px 16px 0;display:grid;grid-template-columns:1fr 1fr;gap:12px">' +
      card('Studio', ['XCODE', '60 FPS'], 'wired', { focus: 1, desks: [3, 1, [2]] }) + card('MacBook Air', ['PAGES', 'DIALOG'], 'wifi', { dlg: 1, warn: 1, desks: [2, 0] }) +
      card('Mac mini', ['LOCKED'], 'vpn', { desks: [1, 0] }) + card('Office iMac', ['OFFLINE 2H'], null, { off: 1 }) + '</div>' +
      '<div class="row" style="gap:8px;padding:16px 16px 0"><span class="pillbtn" style="height:44px;padding:0 14px">' + glyph('lock', 1.8) + 'Lock all</span><span class="pillbtn" style="height:44px;padding:0 14px">' + glyph('pause', 1.8) + 'Pause all</span><span class="pillbtn" style="height:44px;padding:0 14px">' + glyph('send', 1.8) + 'Run on…</span></div></div>';
    return phone(402, 874, t + ' v2', base + sheet);
  };

  S.v2Settings = function (t) {
    function sec(title, rows) { return '<div class="lbl" style="padding:18px 20px 8px">' + title + '</div><div class="list">' + rows.join('') + '</div>'; }
    function r(g, l, trail, sub) { return '<div class="li"><span class="rowic">' + glyph(g, 2) + '</span><span class="li__t">' + l + (sub ? '<small>' + sub + '</small>' : '') + '</span>' + (trail || ic('chevR')) + '</div>'; }
    var inner = '<div class="col">' + sb('pro') + '<div class="hdr hdr2"><span class="grow" style="font:500 22px/1 var(--f-disp);letter-spacing:-.5px">Settings</span><span class="pillbtn pillbtn--accent" style="height:36px">Done</span></div>' +
      '<div class="grow" style="overflow:hidden">' +
      '<div class="subrow"><span class="badge badge--pro">PRO</span><span class="li__t" style="flex:1"><b style="font:600 16px/1.2 var(--f-ui)">Pixel Hand Pro · Yearly</b><small style="color:rgba(255,255,255,.65)">Renews 19 Nov 2027 · Family Sharing on</small></span>' + dmText('PRO', 2, { cls: 'dmt--glow' }) + '</div>' +
      sec('STUDIO', [r('laptop', 'Studio', badge('wired'), 'Paired · protocol 6 · Pixel Hand 1.1'), r('displays', 'Mirror quality', '<span class="trail">Auto</span>' + ic('chevR')), r('audio', 'Play the Mac’s sound', '<span class="tog on"></span>'), r('vpn', 'Reach Studio away from home', '<span class="trail">VPN</span>' + ic('chevR'))]) +
      sec('CONTROL', [r('pointer', 'Trackpad and gestures'), r('keyboard', 'Keyboard'), r('deck', 'Deck and suggestions')]) +
      sec('THIS IPHONE', [r('settings', 'Haptics', '<span class="trail">Light</span>' + ic('chevR')), r('screen', 'Appearance', '<span class="trail">System</span>' + ic('chevR'))]) +
      '<div class="ver">' + dmText('PIXEL HAND 1.1 (52)', 1.4) + '</div></div>' + home('pro') + grid(4, 16, 12) + '</div>';
    return phone(402, 874, t + ' v2', inner);
  };

  S.v2Onboard = function () {
    var inner = '<div class="col brandbg">' + sb('pro', '#fff') +
      '<div class="row" style="padding:4px 20px 0;gap:10px">' + dmText('02/05', 1.6, { cls: 'dmt--glow', label: 'Step 2 of 5' }) + '<span class="grow"></span><span style="font:600 15px/1 var(--f-ui);color:rgba(255,255,255,.7)">Skip</span></div>' +
      '<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:28px;padding:0 28px;text-align:center;position:relative">' +
      '<div class="onb-art">' + glyph('laptop', 10, { off: 1 }) + '<span class="onb-beam"><i class="on"></i><i class="on"></i><i class="on"></i><i></i><i></i></span>' + glyph('iphone', 10, { off: 1 }) + '</div>' +
      '<div><div style="font:500 32px/1.08 var(--f-disp);letter-spacing:-.9px">Get Pixel Hand on your Mac</div><div style="margin-top:12px;font:400 17px/1.4 var(--f-ui);color:rgba(255,255,255,.72)">It’s a free download. Open <b style="color:#fff;font-weight:600">pixelhand.app/mac</b> on the Mac, or send the link there.</div></div>' +
      '<div style="display:flex;flex-direction:column;gap:12px;width:100%"><div class="btnp">Send the link to my Mac</div><div class="btns" style="background:rgba(255,255,255,.1);color:#fff">I already have it</div></div></div>' +
      '<div class="pgd"><i></i><i class="on"></i><i></i><i></i><i></i></div>' + home('pro', '#fff') + grid(4, 16, 12) + '</div>';
    return phone(402, 874, 'dark v2', inner);
  };

  function qr(n, p) {
    var out = '';
    function finder(x0, y0) { for (var y = 0; y < 7; y++) for (var x = 0; x < 7; x++) { var on = x === 0 || y === 0 || x === 6 || y === 6 || (x >= 2 && x <= 4 && y >= 2 && y <= 4); if (on) out += '<rect x="' + (x0 + x) * p + '" y="' + (y0 + y) * p + '" width="' + p * 0.86 + '" height="' + p * 0.86 + '" rx="' + p * 0.26 + '"/>'; } }
    finder(0, 0); finder(n - 7, 0); finder(0, n - 7);
    for (var y = 0; y < n; y++) for (var x = 0; x < n; x++) {
      if ((x < 8 && y < 8) || (x > n - 9 && y < 8) || (x < 8 && y > n - 9)) continue;
      if (hash(y * n + x + 7) > 0.52) out += '<circle cx="' + (x * p + p * 0.43) + '" cy="' + (y * p + p * 0.43) + '" r="' + p * 0.4 + '"/>';
    }
    return '<svg width="' + n * p + '" height="' + n * p + '" viewBox="0 0 ' + n * p + ' ' + n * p + '" aria-label="Pairing QR code (illustration)">' + out + '</svg>';
  }

  S.v2PairMac = function (t) {
    var inner = '<div class="macwin"><div class="macwin__bar"><i></i><i></i><i></i><span>Pair a device</span></div>' +
      '<div class="row" style="gap:28px;padding:24px 28px;align-items:center">' +
      '<div class="qrbox">' + qr(29, 6) + '<span class="qrbox__hand">' + glyph('pointer', 2.2, { cls: 'pg--ph' }) + '</span></div>' +
      '<div style="display:flex;flex-direction:column;gap:14px;flex:1;min-width:0"><b style="font:500 22px/1.15 var(--f-disp);letter-spacing:-.4px">Scan this with your iPhone or iPad</b><span style="font:400 13px/1.45 var(--f-ui);color:var(--ink2)">Or open Pixel Hand there, choose Studio and type the code.</span>' +
      '<div class="navyplate" style="padding:12px 14px;align-items:flex-start"><span style="zoom:.62">' + PH.dmx('4821 0937 552', 11) + '</span></div>' +
      '<div class="row" style="gap:10px;align-items:center"><span class="beam"><i class="on"></i><i class="on"></i><i class="on"></i><i class="on"></i><i class="on"></i><i class="on"></i><i class="on"></i><i></i><i></i><i></i></span><span style="font:500 12px/1 var(--f-ui);color:var(--ink2)">Code works for 3:41 more, for one device</span></div>' +
      '<div class="row" style="gap:8px"><span class="mbtn">New code</span><span class="mbtn">Cancel</span></div></div></div></div>';
    return { w: 560, h: 380, frame: 'bare', html: '<div class="ph v2 ' + t + '" style="width:560px;height:380px;background:' + (t === 'dark' ? 'linear-gradient(160deg,#1b2a7a,#060a2a)' : 'linear-gradient(160deg,#c6dcff,#86b4ff)') + ';display:grid;place-items:center;border-radius:14px">' + inner + '</div>' };
  };

  S.v2PairScan = function () {
    var inner = '<div class="col" style="background:#000">' + sb('pro', '#fff') +
      '<div style="position:absolute;inset:0;background:radial-gradient(60% 40% at 50% 42%,#3a3f52,#0b0c12);opacity:.9"></div>' +
      '<div style="position:absolute;left:50%;top:300px;translate:-50% -50%;width:240px;height:240px">' +
      '<div style="position:absolute;inset:30px;background:#e9ecf5;border-radius:10px;display:grid;place-items:center;color:#121522">' + qr(29, 6).replace('width="174" height="174"', 'width="160" height="160"') + '</div>' +
      '<svg class="vf" width="240" height="240" viewBox="0 0 240 240">' + (function () { var s = ''; for (var i = 0; i < 6; i++) { s += '<rect x="' + (4 + i * 9) + '" y="4" width="6" height="6" rx="2"/><rect x="4" y="' + (4 + i * 9) + '" width="6" height="6" rx="2"/><rect x="' + (230 - i * 9) + '" y="4" width="6" height="6" rx="2"/><rect x="230" y="' + (4 + i * 9) + '" width="6" height="6" rx="2"/><rect x="' + (4 + i * 9) + '" y="230" width="6" height="6" rx="2"/><rect x="4" y="' + (230 - i * 9) + '" width="6" height="6" rx="2"/><rect x="' + (230 - i * 9) + '" y="230" width="6" height="6" rx="2"/><rect x="230" y="' + (230 - i * 9) + '" width="6" height="6" rx="2"/>'; } return s; })() + '</svg>' +
      '<div style="position:absolute;left:12px;right:12px;top:128px;height:1.5px;background:#EFFFFC;box-shadow:0 0 8px #3DE0E0"></div></div>' +
      '<div style="position:absolute;left:24px;right:24px;top:470px;text-align:center;color:#fff"><div style="font:500 24px/1.15 var(--f-disp);letter-spacing:-.5px">Point at the code on your Mac</div><div style="margin-top:10px;font:400 15px/1.4 var(--f-ui);color:rgba(255,255,255,.7)">Menu bar › Pixel Hand › Pair a device</div></div>' +
      '<div style="position:absolute;left:16px;right:16px;bottom:50px;display:flex;flex-direction:column;gap:12px"><div class="toast glass on-navy" style="align-self:center;color:#fff"><i></i>Found Studio · checking its key</div><div class="btns" style="background:rgba(255,255,255,.14);color:#fff">Type the code instead</div></div>' +
      '<span class="grow"></span>' + home('pro', '#fff') + '</div>';
    return phone(402, 874, 'dark v2', inner);
  };

  S.v2Paywall = function () {
    function f(g, t, s) { return '<div class="row" style="gap:12px;align-items:flex-start"><span class="pwic">' + glyph(g, 2.2) + '</span><span><b style="font:600 15px/1.25 var(--f-ui)">' + t + '</b><span style="display:block;margin-top:2px;font:400 13px/1.35 var(--f-ui);color:rgba(255,255,255,.64)">' + s + '</span></span></div>'; }
    var inner = '<div class="col brandbg">' + sb('pro', '#fff') + '<div class="row" style="padding:0 16px;height:44px"><span class="grow"></span><span class="circ" style="background:rgba(255,255,255,.1);color:#fff;width:36px;height:36px">' + glyph('close', 1.6) + '</span></div>' +
      '<div style="padding:0 24px;display:flex;flex-direction:column;gap:20px;position:relative">' +
      '<div class="pwhero">' + dmText('PRO', 5, { off: 1, cls: 'dmt--glow' }) + '</div>' +
      '<div style="font:500 30px/1.1 var(--f-disp);letter-spacing:-.8px">Everything your Mac can do, in your hand.</div>' +
      '<div style="display:flex;flex-direction:column;gap:14px">' + f('deck', 'Decks and app chips', 'Built from each app’s real menus.') + f('screen', 'Live screen, PiP and sound', 'Watch, tap and listen from anywhere in the room.') + f('laptop', 'Every Mac you own', 'Switch with a swipe, run on several at once.') + f('share', 'Send between your devices', 'Clipboard, files, photos and links.') + '</div>' +
      '<div style="display:flex;flex-direction:column;gap:12px">' +
      '<div class="plan-card sel"><span class="radio"></span><span style="flex:1"><b style="font:600 16px/1.2 var(--f-ui)">Yearly · $19.99</b><span style="display:block;font:400 13px/1.3 var(--f-ui);color:rgba(255,255,255,.65)">After 2 weeks free. About $1.67 a month.</span></span><span class="lb lb--mint">' + dmText('-44%', 1.4) + '</span></div>' +
      '<div class="plan-card"><span class="radio"></span><span style="flex:1"><b style="font:600 16px/1.2 var(--f-ui)">Monthly · $2.99</b><span style="display:block;font:400 13px/1.3 var(--f-ui);color:rgba(255,255,255,.65)">After 2 weeks free.</span></span></div></div>' +
      '<div class="btnp">Try 2 weeks free</div>' +
      '<div style="font:400 11px/1.45 var(--f-ui);color:rgba(255,255,255,.56);text-align:center">Free for 2 weeks, then $19.99 a year. Renews automatically until you cancel at least 24 hours before the period ends. Manage it in Settings › Apple Account › Subscriptions.<br><u>Terms of Use</u> · <u>Privacy Policy</u> · <u>Restore Purchases</u></div></div>' +
      '<span class="grow"></span>' + home('pro', '#fff') + grid(4, 24, 12) + '</div>';
    return phone(402, 874, 'dark v2', inner);
  };

  S.v2DuoBook = function (t) {
    var inner = sb('pro').replace('<div class="sb__isl"></div>', '').replace('class="sb"', 'class="sb" style="position:absolute;left:0;right:0;top:0;z-index:5"') +
      '<div class="col" style="flex-direction:row;padding-top:54px">' +
      '<div style="width:455px;flex:none;display:flex;flex-direction:column;gap:12px;padding:0 0 0 16px">' +
      '<div class="mir" style="height:258px;border-radius:24px;flex:none">' + mac({ dlg: true, cur: [52, 44] }) +
      '<div style="position:absolute;left:8px;right:8px;top:8px;display:flex;gap:8px">' + strip(['STUDIO', 'D1/2', 'DESK 2/3', '60 FPS'], { p: 1.6, style: 'height:20px;gap:6px' }) + '</div>' +
      '<div class="mtool glass on-navy" style="position:absolute;right:8px;bottom:8px"><span class="on">' + glyph('click', 2) + '</span><span>' + glyph('displays', 2) + '</span>' + deskDots(3, 1, [2]) + '<span class="on">' + glyph('audio', 2) + '</span><span>' + glyph('pip', 2) + '</span></div></div>' +
      pad({ style: 'margin:0', clicks: true, cap: false, lit: [[200, 100, 54, 1]] }) +
      adock2({ style: 'margin:0 0 16px;height:56px;border-radius:28px' }) + '</div>' +
      '<div style="width:41px;flex:none"></div>' +
      '<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:12px;padding:0 16px 0 0">' + hdr2({ badge: 'wired' }).replace('class="hdr hdr2"', 'class="hdr hdr2" style="padding:0"') +
      '<div class="strip" style="padding:0;gap:8px">' + gchip('', 'Save', '↩', '', 'chip--def') + gchip('', 'Cancel', 'esc', '', 'chip--dlg') + gchip('', 'Don’t Save', '⌘⌫', '', 'chip--dlg') + '</div>' +
      '<div class="row" style="gap:12px">' + app('xcode', 'sm') + '<b style="font:500 20px/1 var(--f-disp);letter-spacing:-.4px;flex:1">Xcode</b>' + pg(3, 1) + '</div>' +
      gdeck(XKEYS.slice(0, 8), 4, 12) + '<span class="grow"></span>' +
      tabs('screen').replace('padding:8px 16px 0', 'padding:0 0 16px') + '</div></div><div class="crease"></div>' +
      '<div class="gridov" style="--c:4;--m:16px;--g:12px;right:auto;width:455px"></div><div class="gridov" style="--c:4;--m:0px;--g:12px;left:496px;right:16px"></div>';
    return phone(951, 669, t + ' v2', inner, { frame: 'fold' });
  };

  S.v2PadLand = function (t) {
    var side = '<div class="side" style="width:232px;padding:8px 0 16px 24px;gap:12px"><div class="row" style="gap:8px;height:44px"><b style="font:500 22px/1 var(--f-disp);letter-spacing:-.4px;flex:1">Macs</b><span class="circ circ--sm">' + glyph('settings', 1.8) + '</span></div>' +
      ['Studio|XCODE|wired|1', 'MacBook Air|DIALOG|wifi|0', 'Mac mini|LOCKED|vpn|0'].map(function (s) { var a = s.split('|'); return '<div class="mcard mcard2' + (a[3] === '1' ? ' focus' : '') + '"><div class="mcard__shot">' + mac({ dlg: a[1] === 'DIALOG' }) + '<div class="mcard2__strip">' + strip([a[1]], { p: 1.3, style: 'height:16px;padding:0 5px;gap:4px;border-radius:6px', cls: a[1] === 'DIALOG' ? 'sstrip--warn' : '' }) + '</div></div><div class="mcard__meta"><b style="flex:1">' + a[0] + '</b>' + badge(a[2]) + '</div></div>'; }).join('') + '</div>';
    var inner = '<div class="col">' + sb('pad') + '<div class="grow" style="display:flex;gap:16px;padding-right:24px">' + side +
      '<div class="grow" style="display:flex;flex-direction:column;gap:12px;position:relative">' +
      '<div class="row" style="gap:12px;height:44px">' + macpill({}) + badge('wired') + '<div class="field glass" style="flex:1;min-width:0;height:44px;font-size:15px;white-space:nowrap">' + glyph('ask', 2) + '<span class="field__ph">Tell Studio…</span><kbd style="font:500 12px/1 var(--f-mono);color:var(--ink3)">⌘K</kbd></div><span class="circ glass">' + glyph('capture', 2.2) + '</span></div>' +
      '<div class="mir" style="height:436px;border-radius:24px;flex:none">' + mac({ dlg: true, cur: [55, 47] }) +
      '<div style="position:absolute;left:12px;right:12px;top:12px;display:flex;gap:8px">' + strip(['STUDIO', 'DISPLAY 1/2', 'DESK 2/3', '60 FPS'], { p: 1.8, style: 'height:22px;gap:6px' }) + '<span class="grow"></span><span class="curbadge">' + glyph('pointer', 1.6) + dmText('ON 2', 1.4) + glyph('arrowR', 1.6) + '</span></div>' +
      '<div class="mtool glass on-navy" style="position:absolute;left:50%;bottom:12px;translate:-50% 0"><span class="on">' + glyph('click', 2) + 'Direct</span><span>' + glyph('displays', 2) + dmText('1/2', 1.6) + '</span><span>' + glyph('arrowL', 2) + '</span>' + deskDots(3, 1, [2]) + '<span>' + glyph('arrowR', 2) + '</span><span class="on">' + glyph('audio', 2) + '</span><span>' + glyph('keyboard', 2) + '</span><span>' + glyph('pip', 2) + '</span></div></div>' +
      pad({ style: 'margin:0 0 88px', clicks: false, cap: false, lit: [[300, 110, 70, 1]] }) +
      adock2({ style: 'position:absolute;left:50%;bottom:16px;translate:-50% 0;width:520px;margin:0;height:56px;border-radius:28px', apps: ['xcode', 'safari', 'terminal', 'figma', 'music', 'messages', 'notes', 'mail', 'finder'] }) + '</div>' +
      '<div style="width:336px;flex:none;display:flex;flex-direction:column;gap:12px">' +
      '<div class="dlgcard"><div class="row" style="gap:8px">' + glyph('close', 1.6, { cls: 'pg--warn' }) + '<b style="font:600 13px/1.25 var(--f-ui);flex:1">Save changes to “Main.swift”?</b></div><div class="row" style="gap:8px">' + gchip('', 'Save', '↩', '', 'chip--def') + gchip('', 'Cancel', '', '', 'chip--dlg') + gchip('', 'Don’t Save', '', '', 'chip--dlg') + '</div></div>' +
      '<div class="row" style="gap:12px;height:44px"><b style="font:500 22px/1 var(--f-disp);letter-spacing:-.4px;flex:1">Xcode</b>' + pg(3, 1) + '<span class="pillbtn" style="height:36px">Edit</span></div>' +
      gdeck(XKEYS, 3, 12) + '</div></div>' + home('pad') + '<div class="gridov" style="--c:12;--m:24px;--g:16px"></div></div>';
    return phone(1180, 820, t + ' v2', inner, { frame: 'ipad' });
  };

  /* ---------- Grid toggle ---------- */
  function addToggle() {
    var row = document.querySelector('.nav__row');
    if (!row || document.getElementById('gridtoggle')) return;
    var b = document.createElement('button');
    b.id = 'gridtoggle'; b.type = 'button'; b.className = 'gridbtn'; b.setAttribute('aria-pressed', 'false'); b.textContent = 'Show layout grid';
    b.addEventListener('click', function () { var on = document.body.classList.toggle('show-grid'); b.setAttribute('aria-pressed', String(on)); b.textContent = on ? 'Hide layout grid' : 'Show layout grid'; });
    row.appendChild(b);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', addToggle); else addToggle();

  PH.glyph = glyph; PH.dmText = dmText; PH.G = G;
})();

/* ---------- Onboarding, every page (round 2b) ---------- */
(function () {
  'use strict';
  var PH = window.PH; if (!PH || !PH.glyph) return;
  var S = PH.S, glyph = PH.glyph, dmText = PH.dmText, mac = PH.mac, hand = PH.hand, lit = PH.lit, sb = PH.sb, home = PH.home, phone = PH.phone;

  var PAGES = [
    { t: 'Pixel Hand', b: 'Your iPhone or iPad becomes a trackpad, a live view of your Mac and a set of buttons for the app in front. Over your own network, with nothing in between.', l: [] },
    { t: 'A real trackpad', b: 'Move, click and scroll with the gestures you already know. The dots light up under your fingers.', l: [['click', 'Two fingers to scroll'], ['mission', 'Three fingers to switch desktops'], ['pointer', 'Tap, then hold to drag']] },
    { t: 'Watch your Mac', b: 'Keep a live view of the screen next to the trackpad. Pinch it bigger to read, flick it to a corner when you’re done.', l: [['pip', 'Drag it anywhere'], ['region', 'Pinch to resize'], ['screen', 'Gets sharper as it grows']] },
    { t: 'Capture and read', b: 'Take the whole screen, one window or a region. Mark it up, or lift the text straight out of it.', l: [['capture', 'Full screen, window or region'], ['type', 'Mark up before you share'], ['ocr', 'Copy the text from any capture']] },
    { t: 'One step on your Mac', b: 'Open Pixel Hand on your Mac. The first time you connect, you pair once with a code from its menu bar.', l: [['laptop', 'Free at pixelhand.app/mac'], ['wifi', 'Same Wi-Fi, or a cable'], ['lock', 'Pair once with a code']] }
  ];

  function strip(txt, style) { return '<div class="sstrip" style="' + style + '"><i class="sstrip__px"></i>' + dmText(txt, 1.6, { cls: 'dmt--glow' }) + '</div>'; }

  /* One dot-art scene per page, all on the same navy plate as the mark. */
  function art(i, s) {
    var k = s / 320;
    if (i === 0) {
      return '<div class="onbmark" style="width:' + s + 'px;height:' + s + 'px"><div class="onbmark__tile" style="width:' + Math.round(s * 0.62) + 'px;height:' + Math.round(s * 0.62) + 'px;border-radius:' + Math.round(s * 0.14) + 'px;padding:' + Math.round(s * 0.07) + 'px"><div class="icon__scr" style="border-radius:' + Math.round(s * 0.08) + 'px">' + hand(Math.round(s * 0.27)) + '<i class="icon__mint" style="right:' + Math.round(s * 0.04) + 'px;top:' + Math.round(s * 0.04) + 'px"></i></div></div></div>';
    }
    var h = '<div class="onbplate" style="width:' + s + 'px;height:' + s + 'px">';
    if (i === 1) {
      var pts = [];
      for (var n = 0; n <= 10; n++) { var t = n / 10; pts.push([s * (0.2 + 0.55 * t), s * (0.74 - 0.42 * t + 0.25 * t * t), 18 + 44 * t, 0.25 + 0.75 * t]); }
      h += lit(pts);
      h += '<i class="onbring" style="left:' + (s * 0.75 - 22) + 'px;top:' + (s * 0.57 - 22) + 'px"></i><i class="onbring" style="left:' + (s * 0.75 + 12) + 'px;top:' + (s * 0.57 - 34) + 'px"></i>';
      h += strip('2 FINGERS · SCROLL', 'position:absolute;left:16px;bottom:16px;height:22px');
    } else if (i === 2 || i === 3) {
      var w = Math.round(s * 0.82), hh = Math.round(w / 1.6), x = (s - w) / 2, y = Math.round(s * 0.2);
      h += '<div class="onbmac" style="left:' + x + 'px;top:' + y + 'px;width:' + w + 'px;height:' + hh + 'px">' + mac({ cur: [46, 42], dlg: i === 2 });
      if (i === 2) {
        h += '<div style="position:absolute;inset:0;background:#000;clip-path:inset(62% 0 0 0)"></div><div style="position:absolute;left:0;right:0;top:calc(62% - 16px);height:16px;background:linear-gradient(transparent,rgba(61,224,224,.45))"></div><div style="position:absolute;left:0;right:0;top:62%;height:1.5px;background:#EFFFFC;box-shadow:0 0 8px #3DE0E0"></div>';
      } else {
        h += '<div class="onbsel" style="left:18%;top:26%;width:52%;height:46%"><i style="left:-4px;top:-4px"></i><i style="right:-4px;top:-4px"></i><i style="left:-4px;bottom:-4px"></i><i style="right:-4px;bottom:-4px"></i></div>';
      }
      h += '</div>';
      h += i === 2 ? strip('LIVE · 60 FPS', 'position:absolute;left:' + (x + 8) + 'px;top:' + (y + 8) + 'px;height:22px') : '<div style="position:absolute;left:' + x + 'px;right:' + x + 'px;top:' + (y + hh + 16 * k) + 'px;display:flex;flex-direction:column;gap:' + Math.round(8 * k) + 'px;color:var(--phosphor)">' + dmText('BUILD FAILED', 1.8 * k, { cls: 'dmt--glow' }) + dmText('MAIN.SWIFT:42', 1.8 * k, { cls: 'dmt--glow' }) + '</div>';
    } else if (i === 4) {
      var p = Math.round(9 * k);
      h += '<div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:' + Math.round(18 * k) + 'px;color:#cfe0ff">' + glyph('wifi', Math.round(4 * k)) +
        '<div class="row" style="gap:' + Math.round(14 * k) + 'px;align-items:center">' + glyph('laptop', p, { off: 1 }) + '<span class="onb-beam"><i class="on"></i><i class="on"></i><i class="on"></i><i></i><i></i></span>' + glyph('iphone', p, { off: 1 }) + '</div>' +
        PH.dmx('4821 0937').replace('class="dmx"', 'class="dmx" style="zoom:' + (0.7 * k).toFixed(2) + '"') + '</div>';
    }
    return h + '</div>';
  }

  function bullets(list, align) {
    if (!list.length) return '';
    return '<div class="onbb" style="align-self:' + (align || 'center') + '">' + list.map(function (b) { return '<div class="onbb__r"><span class="rowic">' + glyph(b[0], 2) + '</span><span>' + b[1] + '</span></div>'; }).join('') + '</div>';
  }
  function dots(i) { var h = '<div class="pgd" aria-hidden="true">'; for (var n = 0; n < 5; n++) h += '<i class="' + (n === i ? 'on' : '') + '"></i>'; return h + '</div>'; }
  function top(i) { return '<div class="row onbtop">' + dmText('0' + (i + 1) + '/05', 1.6, { cls: 'dmt--glow', label: 'Step ' + (i + 1) + ' of 5' }) + '<span class="grow"></span>' + (i < 4 ? '<span class="onbskip">Skip</span>' : '') + '</div>'; }
  function buttons(i, wide) {
    var last = i === 4;
    return '<div class="row" style="gap:12px;width:100%;max-width:' + (wide ? 440 : 420) + 'px">' + (i > 0 ? '<div class="btns onbback">Back</div>' : '') + '<div class="btnp" style="flex:1">' + (last ? 'Find my Mac' : i === 0 ? 'Get started' : 'Continue') + '</div></div>';
  }
  function text(i, align, maxw, tsize) {
    var a = align === 'left' ? 'left' : 'center';
    return '<div style="display:flex;flex-direction:column;gap:12px;text-align:' + a + ';max-width:' + maxw + 'px"><div class="onbt" style="font-size:' + tsize + 'px">' + PAGES[i].t + '</div><div class="onbd">' + PAGES[i].b + '</div></div>';
  }

  /* iPad portrait 820 x 1180 */
  S['onbPad' + 0] = null;
  [0, 1, 2, 3, 4].forEach(function (i) {
    S['onbPadP' + i] = function () {
      var inner = '<div class="col brandbg">' + sb('pad', '#fff') + top(i) +
        '<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:40px;padding:0 48px;position:relative">' + art(i, 340) +
        '<div style="display:flex;flex-direction:column;align-items:center;gap:28px">' + text(i, 'center', 520, 40) + bullets(PAGES[i].l) + '</div></div>' +
        '<div style="display:flex;flex-direction:column;align-items:center;gap:24px;padding:0 48px 24px">' + dots(i) + buttons(i) + '</div>' + home('pad', '#fff') + '</div>';
      return phone(820, 1180, 'dark v2', inner, { frame: 'ipad' });
    };
    S['onbPadL' + i] = function () {
      var inner = '<div class="col brandbg">' + sb('pad', '#fff') + top(i) +
        '<div style="flex:1;display:flex;align-items:center;justify-content:center;gap:72px;padding:0 72px;position:relative">' + art(i, 400) +
        '<div style="display:flex;flex-direction:column;align-items:flex-start;gap:28px;width:440px">' + text(i, 'left', 440, 40) + bullets(PAGES[i].l, 'flex-start') + '<div style="height:4px"></div>' + dots(i).replace('class="pgd"', 'class="pgd" style="justify-content:flex-start;padding:0"') + buttons(i, true) + '</div></div>' + home('pad', '#fff') + '</div>';
      return phone(1180, 820, 'dark v2', inner, { frame: 'ipad' });
    };
    S['onbPhone' + i] = function () {
      var inner = '<div class="col brandbg">' + sb('pro', '#fff') + top(i) +
        '<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:28px;padding:0 24px;position:relative">' + art(i, 248) +
        '<div style="display:flex;flex-direction:column;align-items:center;gap:20px">' + text(i, 'center', 340, 30) + bullets(PAGES[i].l) + '</div></div>' +
        '<div style="display:flex;flex-direction:column;align-items:center;gap:16px;padding:0 24px 8px">' + dots(i) + buttons(i) + '</div>' + home('pro', '#fff') + '</div>';
      return phone(402, 874, 'dark v2', inner);
    };
  });
  delete S.onbPad0;
})();
