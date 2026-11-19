/* Pixel Hand redesign board: renders every mockup from small component
   functions so the screens share one set of parts, the way the SwiftUI
   rebuild will. Sizes are iOS points. Data is example content. */
(function () {
  'use strict';

  /* ---------- Icons (24pt grid, stroke) ---------- */
  var P = {
    pointer: '<path d="M6 3.5l12.5 7.2-5.6 1.4 3.2 5.9-2.3 1.2-3.2-5.9L6 17.5z"/>',
    screen: '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20h6M12 16.5V20"/>',
    deck: '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/>',
    keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2.5"/><path d="M6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M8 14h8" stroke-width="2.2"/>',
    camera: '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><circle cx="12" cy="12" r="3.2"/>',
    more: '<circle cx="5.5" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="18.5" cy="12" r="1.7" fill="currentColor" stroke="none"/>',
    chevD: '<path d="M6 9l6 6 6-6"/>', chevR: '<path d="M9 6l6 6-6 6"/>', chevL: '<path d="M15 6l-6 6 6 6"/>', chevU: '<path d="M6 15l6-6 6 6"/>',
    laptop: '<rect x="4.5" y="5" width="15" height="10.5" rx="1.5"/><path d="M2.5 18.5h19"/>',
    imac: '<rect x="3" y="4" width="18" height="12.5" rx="2"/><path d="M10 16.5l-.8 3.5h5.6l-.8-3.5"/>',
    mini: '<rect x="3.5" y="8" width="17" height="8" rx="2.5"/><path d="M7.5 12.5h3"/>',
    lock: '<rect x="5" y="10.5" width="14" height="9.5" rx="2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    up: '<path d="M12 19V5M6 11l6-6 6 6"/>',
    share: '<path d="M12 15V3.5M7.5 8L12 3.5 16.5 8"/><path d="M5 12v6.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V12"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    x: '<path d="M6 6l12 12M18 6L6 18"/>',
    play: '<path d="M8 5.5v13l10.5-6.5z" fill="currentColor" stroke="none"/>',
    playpause: '<path d="M4 6v12l7.5-6z" fill="currentColor" stroke="none"/><path d="M15 6.5v11M19.5 6.5v11" stroke-width="2.4"/>',
    pause: '<path d="M8.5 5.5v13M15.5 5.5v13" stroke-width="3"/>',
    next: '<path d="M4 6v12l8-6zM12 6v12l8-6z" fill="currentColor" stroke="none"/>',
    prev: '<path d="M20 6v12l-8-6zM12 6v12l-8-6z" fill="currentColor" stroke="none"/>',
    volup: '<path d="M4 9.5h3.5L12 6v12l-4.5-3.5H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>',
    voldown: '<path d="M4 9.5h3.5L12 6v12l-4.5-3.5H4z"/><path d="M15.5 9a4 4 0 0 1 0 6"/>',
    mission: '<rect x="2.5" y="5" width="9" height="6.5" rx="1.5"/><rect x="12.5" y="5" width="9" height="6.5" rx="1.5"/><rect x="7.5" y="13.5" width="9" height="6.5" rx="1.5"/>',
    desktop: '<rect x="3" y="4.5" width="18" height="13" rx="2"/><path d="M7 4.5v13M17 4.5v13"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    sliders: '<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>',
    pip: '<rect x="2.5" y="4.5" width="19" height="15" rx="2.5"/><rect x="12" y="11.5" width="7" height="5.5" rx="1.2" fill="currentColor" stroke="none"/>',
    sidebar: '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M9.5 4.5v15"/>',
    expand: '<path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/>',
    zoom: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5M8.5 11h5M11 8.5v5"/>',
    hammer: '<path d="M13 4.5l6.5 6.5-2.5 2.5L10.5 7z"/><path d="M11.8 9.8L4.5 17.1a1.6 1.6 0 0 0 0 2.3l.1.1a1.6 1.6 0 0 0 2.3 0l7.3-7.3"/>',
    run: '<path d="M7 5v14l11-7z"/>',
    stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
    terminal: '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M7 9.5l3 2.5-3 2.5M12.5 15h4.5"/>',
    pin: '<path d="M9 4h6l-1 6 3.5 3.5h-11L10 10z"/><path d="M12 13.5V20"/>',
    undo: '<path d="M9 7L4.5 11.5 9 16"/><path d="M4.5 11.5H15a4.5 4.5 0 0 1 0 9h-2"/>',
    pencil: '<path d="M4 20l1-4.5L16 4.5l3.5 3.5-11 11z"/>',
    folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2.5h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    photo: '<rect x="3" y="5" width="18" height="14" rx="2.5"/><circle cx="9" cy="10" r="1.6"/><path d="M21 16l-5-5-8 8"/>',
    link: '<path d="M10 14a4 4 0 0 0 5.6 0l3-3a4 4 0 0 0-5.6-5.6l-1 1"/><path d="M14 10a4 4 0 0 0-5.6 0l-3 3a4 4 0 0 0 5.6 5.6l1-1"/>',
    clip: '<rect x="6" y="4.5" width="12" height="16" rx="2"/><path d="M9.5 4.5V3h5v1.5"/>',
    copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5.5A1.5 1.5 0 0 0 14.5 4h-9A1.5 1.5 0 0 0 4 5.5v9A1.5 1.5 0 0 0 5.5 16H8"/>',
    text: '<path d="M3.5 18L8 6l4.5 12M5.2 13.5h5.6M15 13a3 3 0 1 1 0 4.8M20.5 11v7"/>',
    mic: '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
    compass: '<circle cx="12" cy="12" r="8.5"/><path d="M15.5 8.5l-2 5-5 2 2-5z"/>',
    music: '<path d="M9 18V6l10-2v12"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="16.5" cy="16" r="2.5"/>',
    message: '<path d="M4 5.5h16v10.5H9l-5 4z"/>',
    doc: '<path d="M6 3.5h8l4 4v13H6z"/><path d="M14 3.5v4h4"/>',
    moon: '<path d="M19 14.5A7.5 7.5 0 1 1 9.5 5a6 6 0 0 0 9.5 9.5z"/>',
    iphone: '<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
    ipad: '<rect x="4.5" y="2.5" width="15" height="19" rx="2"/><path d="M11 18.5h2"/>',
    window: '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M3 9h18"/>',
    region: '<rect x="4" y="5" width="16" height="14" rx="2" stroke-dasharray="3 2.6"/>',
    ocr: '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2M8 10h8M8 14h5"/>',
    power: '<path d="M12 3.5v8"/><path d="M7 6.5a7.5 7.5 0 1 0 10 0"/>',
    arrowL: '<path d="M19 12H5M11 6l-6 6 6 6"/>', arrowR: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    trash: '<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/>',
    wifiOff: '<path d="M3 3l18 18M8.5 13a5 5 0 0 1 5.4-1M5 9.8a10 10 0 0 1 4.3-2.3M15.3 7.8A10 10 0 0 1 19 9.8M12 18h.01" stroke-width="2"/>',
    warn: '<path d="M12 4l9 16H3z"/><path d="M12 10v4.5M12 17.5h.01" stroke-width="2.2"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M4.4 4.4l2.1 2.1M17.5 17.5l2.1 2.1M2.5 12h3M18.5 12h3M4.4 19.6l2.1-2.1M17.5 6.5l2.1-2.1"/>',
    bolt: '<path d="M13 3L5 13.5h6L10 21l8-10.5h-6z"/>',
    layers: '<path d="M12 4l9 5-9 5-9-5z"/><path d="M3 14l9 5 9-5"/>'
  };
  function ic(n, extra) { return '<svg viewBox="0 0 24 24"' + (extra || '') + '>' + (P[n] || '') + '</svg>'; }

  var STATUS = '<div class="sb__r"><svg viewBox="0 0 18 12"><rect x="1" y="7.5" width="3" height="3.5" rx=".6" fill="currentColor" stroke="none"/><rect x="5.5" y="5.5" width="3" height="5.5" rx=".6" fill="currentColor" stroke="none"/><rect x="10" y="3.5" width="3" height="7.5" rx=".6" fill="currentColor" stroke="none"/><rect x="14.5" y="1.5" width="3" height="9.5" rx=".6" fill="currentColor" stroke="none"/></svg>' +
    '<svg viewBox="0 0 16 12"><path d="M8 10.2h.01" stroke-width="3"/><path d="M4.9 7.4a4.4 4.4 0 0 1 6.2 0M2.4 4.8a8 8 0 0 1 11.2 0"/></svg>' +
    '<svg viewBox="0 0 27 12" style="width:26px"><rect x=".75" y=".75" width="22" height="10.5" rx="3.2" stroke-opacity=".45"/><rect x="2.6" y="2.6" width="16" height="6.8" rx="1.7" fill="currentColor" stroke="none"/><path d="M25 4.6v2.8" stroke-opacity=".45"/></svg></div>';

  function sb(kind, ink) {
    var st = ink ? ' style="color:' + ink + '"' : '';
    if (kind === 'none') return '';
    if (kind === 'se') return '<div class="sb sb--se"' + st + '><span>9:41</span>' + STATUS + '</div>';
    if (kind === 'pad') return '<div class="sb sb--pad"' + st + '><span>9:41 Tue 17 Nov</span>' + STATUS + '</div>';
    return '<div class="sb"' + st + '><span>9:41</span><div class="sb__isl"></div>' + STATUS + '</div>';
  }
  function home(kind, ink) {
    if (kind === 'none') return '<div class="home home--none"></div>';
    var st = ink ? ' style="--ink:' + ink + '"' : '';
    return '<div class="home' + (kind === 'pad' ? ' home--pad' : '') + '"' + st + '></div>';
  }

  /* ---------- App icons ---------- */
  var APPS = {
    xcode: ['t-blue', 'hammer'], safari: ['t-teal', 'compass'], pages: ['t-orange', 'doc'], music: ['t-pink', 'music'],
    messages: ['t-green', 'message'], finder: ['t-navy', 'folder'], terminal: ['t-gray', 'terminal'], photos: ['t-yellow', 'photo'],
    figma: ['t-purple', 'pencil'], mail: ['t-blue', 'up'], notes: ['t-yellow', 'doc'], slack: ['t-purple', 'message']
  };
  function app(n, size) {
    var a = APPS[n] || ['t-gray', 'window'];
    return '<span class="ai ' + a[0] + (size ? ' ai--' + size : '') + '">' + ic(a[1]) + '</span>';
  }

  /* ---------- Fake Mac screen ---------- */
  function mac(o) {
    o = o || {};
    var h = '<div class="macs"><div class="macs__bar"><i style="width:1.2cqw"></i><i style="width:3cqw"></i><i style="width:2.4cqw;opacity:.6"></i><i style="width:2.4cqw;opacity:.6"></i><i style="width:2cqw;opacity:.6"></i><span style="flex:1"></span><i style="width:5cqw;opacity:.7"></i></div>' +
      '<div class="macs__win"><div class="macs__side"><div class="macs__lights"><b></b><b></b><b></b></div><i style="width:70%"></i><i class="sel"></i><i style="width:60%"></i><i style="width:80%"></i><i style="width:50%"></i><i style="width:70%"></i></div>' +
      '<div class="macs__main"><i style="width:40%"></i><i class="k" style="width:22%"></i><i style="width:64%"></i><i class="b" style="width:48%"></i><i style="width:72%"></i><i class="s" style="width:36%"></i><i style="width:58%"></i><i class="k" style="width:28%"></i><i style="width:66%"></i><i style="width:44%"></i><i class="b" style="width:52%"></i></div></div>';
    if (o.dlg) h += '<div class="macs__dlg"><i class="t"></i><i></i><i style="width:64%"></i><u></u><u></u><u class="d"></u></div>';
    h += '<div class="macs__dock"><b class="t-blue"></b><b class="t-teal"></b><b class="t-orange"></b><b class="t-pink"></b><b class="t-green"></b><b class="t-navy"></b><b class="t-gray"></b></div>';
    if (o.cur) h += '<div class="macs__cur" style="left:' + o.cur[0] + '%;top:' + o.cur[1] + '%"></div>';
    if (o.dim) h += '<div style="position:absolute;inset:0;background:rgba(6,10,42,.66)"></div>';
    return h + '</div>';
  }

  /* ---------- Trackpad pieces ---------- */
  function lit(points) {
    var out = '';
    points.forEach(function (p) {
      var cx = p[0], cy = p[1], r = p[2], amp = p[3] == null ? 1 : p[3];
      for (var gx = 7.5; gx < cx + r + 1; gx += 15) {
        for (var gy = 7.5; gy < cy + r + 1; gy += 15) {
          var d = Math.hypot(gx - cx, gy - cy);
          if (d > r) continue;
          var t = Math.pow(1 - d / r, 1.5) * amp;
          if (t < 0.06) continue;
          var s = 2.4 + 2.6 * t;
          out += '<i class="pad__lit" style="left:' + (gx - s / 2).toFixed(1) + 'px;top:' + (gy - s / 2).toFixed(1) + 'px;width:' + s.toFixed(1) + 'px;height:' + s.toFixed(1) + 'px;opacity:' + (0.25 + 0.75 * t).toFixed(2) + ';box-shadow:0 0 ' + (3 + 8 * t).toFixed(1) + 'px rgba(61,224,224,' + (0.9 * t).toFixed(2) + ')"></i>';
        }
      }
    });
    return out;
  }
  function pad(o) {
    o = o || {};
    var h = '<div class="pad ' + (o.cls || 'grow') + '" style="' + (o.style || 'margin:0 12px') + '">';
    if (o.lit) h += lit(o.lit);
    if (o.cap !== false) h += '<div class="pad__cap"><i></i>' + (o.cap || 'Two fingers to scroll') + '</div>';
    if (o.hint) h += '<div class="pad__hint">' + o.hint + '</div>';
    if (o.mirror) h += '<div class="mir" style="position:absolute;' + o.mirror + '">' + mac({ cur: [44, 40], dlg: o.dlg }) + '<div class="mir__live"><i></i>LIVE</div></div>';
    if (o.clicks) h += '<div class="pad__clicks"><span>Click</span><span>Right-click</span></div>';
    if (o.extra) h += o.extra;
    return h + '</div>';
  }

  /* ---------- Header ---------- */
  function macpill(o) {
    o = o || {};
    return '<div class="macpill glass' + (o.off ? ' off' : '') + '"><span class="macpill__glyph">' + ic(o.glyph || 'imac') + '</span><span class="macpill__txt"><b>' + (o.name || 'Studio') + '</b><span>' + (o.sub || 'Xcode') + '</span></span>' + ic('chevD') + '</div>';
  }
  function header(o) {
    o = o || {};
    return '<div class="hdr">' + macpill(o) + '<span class="grow"></span>' + (o.trailing || ['camera', 'more']).map(function (n) { return '<span class="circ glass">' + ic(n) + '</span>'; }).join('') + '</div>';
  }

  /* ---------- Chips and strip ---------- */
  function chip(l, k, st, cls) {
    return '<span class="chip ' + (st ? 'chip--' + st : '') + ' ' + (cls || '') + '"><span class="chip__l">' + l + (k ? '<kbd>' + k + '</kbd>' : '') + '</span><span class="chip__dots"><i></i><i></i><i></i></span></span>';
  }
  function strip(kind, o) {
    o = o || {};
    var h = '<div class="strip ' + (o.cls || 'fade-r') + '" style="' + (o.style || '') + '">';
    if (kind === 'dialog') {
      h += (o.label ? '<span class="strip__lbl">Save changes to “Main.swift”?</span>' : '') + chip('Save', '↩', '', 'chip--def') + chip('Cancel', 'esc', '', 'chip--dlg') + chip("Don’t Save", '⌘⌫', '', 'chip--dlg');
    } else if (kind === 'free') {
      h += chip(ic('prev').replace('<svg', '<svg style="width:16px;height:16px"'), '', '') + chip(ic('playpause').replace('<svg', '<svg style="width:18px;height:16px"'), '', 'ok') + chip(ic('next').replace('<svg', '<svg style="width:16px;height:16px"'), '', '') + chip(ic('voldown').replace('<svg', '<svg style="width:17px;height:17px"'), '', '') + chip(ic('volup').replace('<svg', '<svg style="width:17px;height:17px"'), '', '') + '<span class="chip chip--ai"><span class="chip__l" style="font-size:14px">App chips · Pro</span></span>';
    } else {
      h += chip('Build', '⌘B', 'ok') + chip('Run', '⌘R', 'send') + chip('Stop', '⌘.') + chip('Open Quickly', '⇧⌘O') + '<span class="chip chip--ai"><span class="chip__l">+ Suggest</span></span>';
    }
    return h + '</div>';
  }

  /* ---------- Docks ---------- */
  function appDock(o) {
    o = o || {};
    var list = o.apps || ['xcode', 'safari', 'terminal', 'figma', 'music', 'messages', 'notes'];
    var front = o.front || 'xcode';
    var h = '<div class="adock glass" style="' + (o.style || '') + '"><span class="adock__apps">';
    list.forEach(function (n) { h += '<span class="adock__app' + (n === front ? ' front' : '') + '">' + app(n) + '</span>'; });
    h += '</span><span class="adock__div"></span><span class="circ circ--sm">' + ic('keyboard') + '</span></div>';
    return h;
  }
  function surfaceDock(sel, o) {
    o = o || {};
    var tabs = [['pointer', 'Pointer'], ['screen', 'Screen'], ['deck', 'Deck']];
    var h = '<div class="sdock" style="' + (o.style || '') + '">';
    if (o.min) {
      var t = tabs.filter(function (x) { return x[0] === sel; })[0];
      h += '<div class="tabs tabs--min glass"><span class="on">' + ic(t[0]) + '</span></div><span class="grow"></span>';
    } else {
      h += '<div class="tabs glass">' + tabs.map(function (t) { return '<span class="' + (t[0] === sel ? 'on' : '') + '">' + ic(t[0]) + t[1] + '</span>'; }).join('') + '</div>';
    }
    h += '<span class="ask glass"><span class="dotask"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span></span></div>';
    return h;
  }

  /* ---------- Deck ---------- */
  var XCODE_KEYS = [
    { g: 'hammer', l: 'Build', k: '⌘B', s: 'ok' }, { g: 'run', l: 'Run', k: '⌘R', s: 'send' }, { g: 'stop', l: 'Stop', k: '⌘.' }, { g: 'check', l: 'Test', k: '⌘U' },
    { g: 'search', l: 'Open Quickly', k: '⇧⌘O' }, { g: 'sidebar', l: 'Navigator', k: '⌘0' }, { g: 'terminal', l: 'Console', k: '⇧⌘C' }, { g: 'trash', l: 'Clean Build', k: '⇧⌘K', ask: 1 },
    { g: 'link', l: 'Jump to Definition', k: '⌃⌘J' }, { g: 'doc', l: 'Comment', k: '⌘/' }, { g: 'screen', l: 'Canvas', k: '⌥⌘↩' }, { g: 'mission', l: 'Mission Control', navy: 1 }
  ];
  function key(k) {
    var cls = 'key' + (k.s ? ' key--' + k.s : '') + (k.ask ? ' key--ask' : '') + (k.navy ? ' key--navy' : '') + (k.ghost ? ' key--ghost' : '') + (k.edit ? ' key--edit' : '');
    var g = k.app ? app(k.app, 'sm') : (k.px ? k.px : ic(k.g));
    return '<span class="' + cls + '"><span class="key__g">' + g + '</span><span class="key__l">' + k.l + '</span>' + (k.k ? '<span class="key__k">' + k.k + '</span>' : '') + '<span class="key__s"><i></i><i></i><i></i><i></i></span></span>';
  }
  function deck(keys, cols, gap) {
    return '<div class="deck" style="grid-template-columns:repeat(' + cols + ',minmax(0,1fr));gap:' + (gap || 10) + 'px">' + keys.map(key).join('') + '</div>';
  }
  function pixel(rows) {
    var h = '<span class="px8">';
    rows.forEach(function (r) { for (var i = 0; i < 8; i++) h += '<i class="' + (r[i] === '#' ? 'on' : '') + '"></i>'; });
    return h + '</span>';
  }
  var GLYPH_ROCKET = pixel(['...##...', '..####..', '..#..#..', '..####..', '.######.', '.##..##.', '...##...', '..#..#..']);

  /* ---------- Dot-matrix numerals (3x5) ---------- */
  var DIG = { 0: '111101101101111', 1: '010110010010111', 2: '111001111100111', 3: '111001111001111', 4: '101101111001001', 5: '111100111001111', 6: '111100111101111', 7: '111001010010010', 8: '111101111101111', 9: '111101111001111' };
  function dmx(str, dimFrom) {
    var h = '<span class="dmx">';
    str.split('').forEach(function (c, i) {
      if (c === ' ') { h += '<span class="dmx__sp"></span>'; return; }
      var bits = DIG[c] || '000000000000000';
      h += '<span class="dmx__d' + (dimFrom != null && i >= dimFrom ? ' dim' : '') + '">';
      for (var b = 0; b < 15; b++) h += '<i class="' + (bits[b] === '1' ? 'on' : '') + '"></i>';
      h += '</span>';
    });
    return h + '</span>';
  }

  /* ---------- The pixel hand (12 x 17, from the icon) ---------- */
  var HAND = ['p...........', 'pp..........', 'pvp.........', 'pvvp........', 'pvvvp.......', 'pvvvvp......', 'pvvvvvp.....', 'pvvvvvvp....', 'pvvvvvvvp...', 'pvvvvvvvvp..', 'pvvvvvpppp..', 'pvvpvvp.....', 'pvp.pvvp....', 'pp..pvvp....', 'p....pvvp...', '.....pvvp...', '......pp....'];
  function hand(w) {
    var h = '<span class="hand" style="width:' + w + 'px">';
    HAND.forEach(function (r) { for (var i = 0; i < 12; i++) { var c = r[i]; h += '<i class="' + (c === 'p' ? 'p' : c === 'v' ? 'v' : '') + '"></i>'; } });
    return h + '</span>';
  }

  /* ---------- Screen wrapper ---------- */
  function phone(w, h, theme, inner, o) {
    o = o || {};
    return { w: w, h: h, frame: o.frame || 'iphone', html: '<div class="ph ' + theme + ' ' + (o.cls || '') + '" style="width:' + w + 'px;height:' + h + 'px">' + inner + '</div>' };
  }

  var S = {};

  /* iPhone, Pointer surface */
  S.phPointer = function (t, o) {
    o = o || {};
    var w = o.w || 402, h = o.h || 874;
    var inner = '<div class="col">' + sb(o.sb || 'pro') + header({ sub: o.free ? 'Music' : 'Xcode' }) +
      pad({ mirror: o.noMirror ? null : 'right:12px;top:12px;width:176px;height:110px', dlg: o.strip === 'dialog', clicks: true, lit: [[150, 300, 70, 1], [110, 340, 40, 0.5], [80, 368, 28, 0.25]] }) +
      strip(o.free ? 'free' : (o.strip || 'dialog'), { style: 'margin-top:6px' }) +
      appDock({ front: o.free ? 'music' : 'xcode' }) + surfaceDock('pointer', { style: 'padding-top:10px' }) + home(o.home || 'pro') + '</div>';
    return phone(w, h, t, inner);
  };

  /* iPhone, Deck surface */
  S.phDeck = function (t) {
    var inner = '<div class="col">' + sb('pro') + header() +
      '<div class="grow" style="display:flex;flex-direction:column;gap:12px;padding-top:6px">' +
      '<div class="shead">' + app('xcode', 'sm') + '<div style="display:flex;flex-direction:column;gap:2px;flex:1;min-width:0"><h5>Xcode</h5><small>Follows the front app · page 1 of 3</small></div><span class="pillbtn">' + ic('pin') + '</span><span class="pillbtn">Edit</span></div>' +
      '<div style="padding:0 16px">' + deck(XCODE_KEYS, 4) + '</div>' +
      '<div class="pg"><i class="on"></i><i></i><i></i></div>' +
      '<div style="margin:2px 16px 0;padding:12px;border-radius:22px;background:var(--accent-tint);display:flex;flex-direction:column;gap:10px">' +
      '<div class="row" style="gap:8px"><span class="dotask" style="color:var(--accent-ink)"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span><b style="font:600 14px/1.2 var(--f-ui);color:var(--accent-ink);flex:1">3 suggestions from Xcode’s menus</b><span class="pillbtn pillbtn--accent" style="height:30px">Keep all</span></div>' +
      deck([{ g: 'doc', l: 'Show Minimap', k: '⌃⇧⌘M', ghost: 1 }, { g: 'sliders', l: 'Scheme…', k: '⌘<', ghost: 1 }, { g: 'undo', l: 'Discard Changes', k: '⌥⌘C', ghost: 1 }, { g: 'plus', l: 'Edit page', ghost: 1 }], 4, 8) + '</div>' +
      '</div>' + strip('dialog', { style: 'margin-top:8px' }) + appDock() + surfaceDock('deck', { style: 'padding-top:10px' }) + home('pro') + '</div>';
    return phone(402, 874, t, inner);
  };

  /* iPhone, Screen surface: mirror docked big, follow-cursor zoom, trackpad below */
  S.phScreen = function (t) {
    var inner = '<div class="col">' + sb('pro') + header() +
      '<div style="margin:2px 12px 0;position:relative;height:300px;border-radius:24px;overflow:hidden;background:#000;flex:none">' +
      '<div style="position:absolute;left:-40%;top:-30%;width:200%;height:200%">' + mac({ dlg: true, cur: [47, 33] }) + '</div>' +
      '<div style="position:absolute;left:10px;top:10px" class="stats">60 fps · 7 ms · HEVC 1920</div>' +
      '<div style="position:absolute;right:10px;top:10px;width:88px;height:55px;border-radius:8px;overflow:hidden;box-shadow:0 0 0 1px rgba(255,255,255,.4)">' + mac({ dlg: true }) + '<span style="position:absolute;left:24%;top:20%;width:50%;height:50%;box-shadow:inset 0 0 0 1.5px #9ff6ff;border-radius:3px"></span></div>' +
      '<div class="mtool glass on-navy" style="position:absolute;left:50%;bottom:10px;translate:-50% 0"><span class="on">' + ic('pointer') + 'Direct</span><span>' + ic('zoom') + '2×</span><span>' + ic('screen') + '</span><span>' + ic('pip') + '</span><span>' + ic('expand') + '</span></div>' +
      '</div>' +
      pad({ style: 'margin:10px 12px 0', cap: 'Trackpad · follows the cursor', lit: [[220, 120, 50, 0.8]] }) +
      strip('dialog', { style: 'margin-top:6px' }) + appDock() + surfaceDock('screen', { style: 'padding-top:10px' }) + home('pro') + '</div>';
    return phone(402, 874, t, inner);
  };

  /* iPhone, Ask (command bar) */
  S.phAsk = function (t) {
    var base = S.phPointer(t, { strip: 'app' }).html.replace(/^<div class="ph [^"]*" style="[^"]*">/, '').replace(/<\/div>$/, '');
    var sheet = '<div class="scrim"></div><div class="sheet-ui" style="height:520px"><div class="grab"></div>' +
      '<div class="sheet-ui__h"><span class="dotask" style="color:var(--ink)"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span><h6>Ask Studio</h6><span class="pillbtn">On device</span></div>' +
      '<div style="padding:4px 16px 0"><div class="field"><span style="flex:1">Open the build log and copy the first error</span><span class="field__go">' + ic('up') + '</span></div></div>' +
      '<div style="padding:16px 16px 0;display:flex;flex-direction:column;gap:10px"><div class="lbl" style="padding:0 4px">Plan · 3 steps on Studio</div></div>' +
      '<div class="plan" style="margin-top:8px"><div class="scan"></div>' +
      '<div class="plan__step"><span class="plan__n">1</span>Show the Report navigator<kbd>⌘9</kbd></div>' +
      '<div class="plan__step"><span class="plan__n">2</span>Open the latest build log<kbd>menu</kbd></div>' +
      '<div class="plan__step"><span class="plan__n">3</span>Read the first error and copy it here<kbd>OCR</kbd></div>' +
      '<div class="row" style="gap:8px;margin-top:4px"><span class="pillbtn pillbtn--accent" style="height:40px;padding:0 18px;font-size:15px">' + ic('play') + 'Run</span><span class="pillbtn" style="height:40px">Save as key</span><span class="grow"></span><span class="pillbtn" style="height:40px">Edit</span></div></div>' +
      '<div class="lbl" style="margin-top:16px">Try</div>' +
      '<div class="strip" style="flex-wrap:wrap;white-space:normal;padding:8px 16px">' + chip('Lock all my Macs') + chip('Mute Studio') + chip('What’s on screen?') + '</div></div>';
    return phone(402, 874, t, base + sheet);
  };

  /* iPhone, Mac switcher sheet (multi-Mac, 1.3) */
  S.phMacs = function (t) {
    var base = S.phPointer(t, { strip: 'app' }).html.replace(/^<div class="ph [^"]*" style="[^"]*">/, '').replace(/<\/div>$/, '');
    function card(name, sub, glyph, opt) {
      opt = opt || {};
      return '<div class="mcard' + (opt.focus ? ' focus' : '') + '"><div class="mcard__shot' + (opt.off ? ' off' : '') + '">' + mac({ dlg: opt.dlg, cur: [40, 50] }) + (opt.badge ? '<span class="badge" style="position:absolute;left:6px;bottom:6px;z-index:3">' + opt.badge + '</span>' : '') + '</div><div class="mcard__meta"><span class="ldot' + (opt.off ? ' off' : opt.warn ? ' warn' : '') + '"></span><span style="flex:1;min-width:0"><b>' + name + '</b><small>' + sub + '</small></span></div></div>';
    }
    var sheet = '<div class="scrim"></div><div class="sheet-ui" style="height:600px"><div class="grab"></div>' +
      '<div class="sheet-ui__h"><h6>My Macs</h6><span class="pillbtn">' + ic('plus') + 'Add</span></div>' +
      '<div style="padding:8px 16px 0;display:grid;grid-template-columns:1fr 1fr;gap:12px">' +
      card('Studio', 'Xcode · focused', 'imac', { focus: 1 }) + card('MacBook Air', 'Pages · dialog waiting', 'laptop', { dlg: 1, warn: 1, badge: 'Dialog' }) +
      card('Mac mini', 'Locked', 'mini', { badge: 'Locked' }) + card('Office iMac', 'Last seen 2 h ago', 'imac', { off: 1 }) + '</div>' +
      '<div class="lbl" style="margin-top:18px">Swipe the Mac name left or right, or use three fingers on the trackpad, to switch.</div>' +
      '<div class="row" style="gap:8px;padding:14px 16px 0"><span class="pillbtn" style="height:40px">' + ic('lock') + 'Lock all</span><span class="pillbtn" style="height:40px">' + ic('playpause') + 'Pause all</span><span class="pillbtn" style="height:40px">Run on…</span></div></div>';
    return phone(402, 874, t, base + sheet);
  };

  /* iPhone landscape: leading rail, trackpad, deck column */
  S.phLand = function (t) {
    var inner = '<div class="col" style="flex-direction:row;padding:10px 0 6px 52px;gap:10px">' +
      '<div class="rail glass" style="width:60px">' + '<span class="macpill__glyph" style="width:40px;height:40px;border-radius:12px">' + ic('imac') + '</span>' +
      '<span class="circ on">' + ic('pointer') + '</span><span class="circ">' + ic('screen') + '</span><span class="circ">' + ic('deck') + '</span><span class="grow"></span><span class="circ">' + ic('keyboard') + '</span><span class="circ"><span class="dotask"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span></span></div>' +
      pad({ cls: 'grow', style: 'margin:0', mirror: 'right:12px;top:12px;width:150px;height:94px', clicks: true, lit: [[160, 170, 60, 1], [120, 210, 34, 0.5]] }) +
      '<div style="width:300px;flex:none;display:flex;flex-direction:column;gap:8px;padding-right:46px;box-sizing:content-box">' +
      '<div class="row" style="gap:8px">' + app('xcode', 'sm') + '<b style="font:600 16px/1 var(--f-ui);flex:1">Xcode</b><span class="circ circ--sm glass">' + ic('camera') + '</span><span class="circ circ--sm glass">' + ic('more') + '</span></div>' +
      '<div class="strip" style="padding:0;gap:6px;flex-wrap:wrap;white-space:normal">' + chip("Don’t Save", '', '', 'chip--dlg') + chip('Cancel', '', '', 'chip--dlg') + chip('Save', '↩', '', 'chip--def') + '</div>' +
      deck(XCODE_KEYS.slice(0, 6), 3, 8) + '<div class="pg"><i class="on"></i><i></i><i></i><i></i></div></div></div>';
    return phone(874, 402, t, inner, { frame: 'land' });
  };

  /* iPhone SE: tab bar minimised, app dock folded into the strip */
  S.phSE = function (t) {
    var inner = '<div class="col">' + sb('se') + '<div class="hdr" style="height:48px">' + macpill() + '<span class="grow"></span><span class="circ glass circ--sm">' + ic('camera') + '</span><span class="circ glass circ--sm">' + ic('more') + '</span></div>' +
      pad({ mirror: 'right:10px;top:10px;width:132px;height:82px', clicks: true, lit: [[140, 200, 56, 1]] }) +
      '<div class="strip fade-r" style="margin-top:6px"><span class="chip chip--app">' + app('xcode', 'sm') + ic('chevU') + '</span>' + chip('Build', '⌘B', 'ok') + chip('Run', '⌘R') + chip('Stop', '⌘.') + '</div>' +
      surfaceDock('pointer', { min: 1, style: 'padding:4px 12px 8px' }) + '</div>';
    var o = phone(375, 667, t, inner, { frame: 'se' });
    return o;
  };

  /* iPhone Duo cover display (466 x 678) */
  S.duoCover = function (t) { var o = S.phPointer(t, { w: 466, h: 678, strip: 'app', noMirror: false }); o.frame = 'fold'; return o; };

  /* iPhone Duo open, book pose: two panes, nothing on the crease */
  S.duoBook = function (t) {
    var inner = sb('pro').replace('<div class="sb__isl"></div>', '').replace('class="sb"', 'class="sb" style="position:absolute;left:0;right:0;top:0;z-index:5"') +
      '<div class="col" style="flex-direction:row;padding-top:54px">' +
      '<div style="width:455px;flex:none;display:flex;flex-direction:column;gap:10px;padding:4px 0 0 14px">' +
      '<div class="mir" style="height:262px;border-radius:22px;flex:none">' + mac({ dlg: true, cur: [52, 44] }) + '<div class="mir__live"><i></i>LIVE</div>' +
      '<div class="mtool glass on-navy" style="position:absolute;right:10px;bottom:10px"><span class="on">' + ic('pointer') + '</span><span>' + ic('zoom') + '</span><span>' + ic('pip') + '</span><span>' + ic('expand') + '</span></div></div>' +
      pad({ style: 'margin:0', clicks: true, cap: 'Trackpad', lit: [[200, 110, 54, 1]] }) +
      appDock({ style: 'margin:0 0 14px' }) + '</div>' +
      '<div style="width:41px;flex:none"></div>' +
      '<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:10px;padding:0 14px 0 0">' + header().replace('class="hdr"', 'class="hdr" style="padding:0"') +
      '<div class="strip" style="padding:0;gap:6px;flex-wrap:wrap;white-space:normal"><span class="strip__lbl" style="max-width:none;width:100%">Save changes to “Main.swift”?</span>' + chip("Don’t Save", '⌘⌫', '', 'chip--dlg') + chip('Cancel', 'esc', '', 'chip--dlg') + chip('Save', '↩', '', 'chip--def') + '</div>' +
      '<div class="row" style="gap:8px;margin-top:4px">' + app('xcode', 'sm') + '<b style="font:600 18px/1 var(--f-disp);flex:1">Xcode</b><span class="pillbtn">Edit</span></div>' +
      deck(XCODE_KEYS.slice(0, 8), 4, 8) + '<div class="pg"><i class="on"></i><i></i><i></i></div><span class="grow"></span>' +
      surfaceDock('screen', { style: 'padding:0 0 14px' }) + '</div></div><div class="crease"></div>';
    return phone(951, 669, t, inner, { frame: 'fold' });
  };

  /* iPhone Duo half-folded, laptop pose: screen above the fold, controls below */
  S.duoLaptop = function (t) {
    var inner = '<div class="col">' + sb('pro') +
      '<div class="row" style="gap:10px;padding:0 14px 8px">' + macpill() + '<span class="grow"></span><span class="circ glass">' + ic('camera') + '</span><span class="circ glass">' + ic('more') + '</span></div>' +
      '<div class="mir" style="margin:0 14px;height:340px;border-radius:24px;flex:none">' + mac({ dlg: true, cur: [52, 44] }) + '<div class="mir__live"><i></i>LIVE</div><div class="stats" style="position:absolute;right:10px;top:10px">60 fps · 6 ms</div></div>' +
      '<div style="height:42px;flex:none"></div>' +
      strip('dialog') + pad({ style: 'margin:4px 14px 0', clicks: true, lit: [[300, 110, 60, 1]] }) +
      surfaceDock('screen', { style: 'padding-top:10px' }) + home('pro') + '</div>' +
      '<div class="crease" style="left:0;right:0;top:455px;bottom:auto;width:auto;height:41px;background:linear-gradient(90deg,transparent,rgba(255,255,255,.07) 15%,rgba(255,255,255,.07) 85%,transparent)"></div>';
    return phone(669, 951, t, inner, { frame: 'fold' });
  };

  /* iPad landscape (1180 x 820): Macs sidebar | screen + trackpad | deck column */
  function padSidebar(focusName) {
    function m(name, sub, opt) {
      opt = opt || {};
      return '<div class="mcard' + (name === focusName ? ' focus' : '') + '"><div class="mcard__shot' + (opt.off ? ' off' : '') + '">' + mac({ dlg: opt.dlg }) + (opt.badge ? '<span class="badge" style="position:absolute;left:5px;bottom:5px;z-index:3">' + opt.badge + '</span>' : '') + '</div><div class="mcard__meta"><span class="ldot' + (opt.off ? ' off' : opt.warn ? ' warn' : '') + '"></span><span style="flex:1;min-width:0"><b>' + name + '</b><small>' + sub + '</small></span></div></div>';
    }
    return '<div class="side" style="width:228px;padding:6px 0 12px 14px"><div class="row" style="gap:8px;padding:4px 2px 2px"><b style="font:600 22px/1 var(--f-disp);letter-spacing:-.4px;flex:1">Macs</b><span class="circ circ--sm">' + ic('sidebar') + '</span></div>' +
      m('Studio', 'Xcode', {}) + m('MacBook Air', 'Pages · dialog', { dlg: 1, warn: 1, badge: 'Dialog' }) + m('Mac mini', 'Locked', { badge: 'Locked' }) +
      '<span class="grow"></span><div class="lbl" style="padding:0 2px">Send to Studio</div><div style="padding:14px;border-radius:16px;border:1.5px dashed var(--fill2);color:var(--ink2);font:500 13px/1.35 var(--f-ui);text-align:center">Drop files, photos or links on a Mac</div></div>';
  }
  S.padLand = function (t) {
    var inner = '<div class="col">' + sb('pad') + '<div class="grow" style="display:flex;gap:14px;padding-right:14px">' + padSidebar('Studio') +
      '<div class="grow" style="display:flex;flex-direction:column;gap:12px;position:relative">' +
      '<div class="row" style="gap:10px;padding-top:4px">' + macpill() + '<div class="tabs glass" style="flex:none;height:42px;border-radius:21px;padding:3px"><span class="on" style="flex-direction:row;height:36px;padding:0 12px;font-size:13px;gap:6px;width:auto" aria-label="Split">' + ic('layers') + '</span><span style="flex-direction:row;height:36px;padding:0 12px;font-size:13px;width:auto">' + ic('screen') + '</span><span style="flex-direction:row;height:36px;padding:0 12px;font-size:13px;width:auto">' + ic('pointer') + '</span></div>' +
      '<div class="field glass" style="flex:1;min-width:0;height:42px;font-size:15px;white-space:nowrap"><span class="dotask" style="color:var(--ink)"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span><span class="field__ph">Tell Studio…</span><kbd style="font:500 12px/1 var(--f-mono);color:var(--ink3)">⌘K</kbd></div>' +
      '<span class="circ glass">' + ic('camera') + '</span><span class="circ glass">' + ic('more') + '</span></div>' +
      '<div class="mir" style="height:440px;border-radius:24px;flex:none">' + mac({ dlg: true, cur: [55, 47] }) + '<div class="mir__live"><i></i>LIVE</div>' +
      '<div class="stats" style="position:absolute;right:12px;top:12px">60 fps · 6 ms frame · 4/11 ms RTT · HEVC 1920</div>' +
      '<div class="mtool glass on-navy" style="position:absolute;left:50%;bottom:12px;translate:-50% 0"><span class="on">' + ic('pointer') + 'Direct</span><span>' + ic('zoom') + '</span><span>' + ic('screen') + 'Display 1</span><span>' + ic('keyboard') + '</span><span>' + ic('pip') + '</span><span>' + ic('expand') + '</span></div></div>' +
      pad({ style: 'margin:0 0 84px', clicks: false, cap: 'Trackpad', lit: [[300, 120, 70, 1], [250, 150, 40, 0.5]] }) +
      appDock({ style: 'position:absolute;left:50%;bottom:16px;translate:-50% 0;width:520px;margin:0', apps: ['xcode', 'safari', 'terminal', 'figma', 'music', 'messages', 'notes', 'mail', 'finder'] }) + '</div>' +
      '<div style="width:330px;flex:none;display:flex;flex-direction:column;gap:12px;padding-top:4px">' +
      '<div style="padding:12px;border-radius:22px;background:var(--raised);box-shadow:inset 0 0 0 .5px var(--hair);display:flex;flex-direction:column;gap:10px"><div class="row" style="gap:8px">' + app('xcode', 'sm') + '<b style="font:600 13px/1.25 var(--f-ui);flex:1">Save changes to “Main.swift”?</b><span class="badge">Dialog</span></div>' +
      '<div class="row" style="gap:6px">' + chip("Don’t Save", '⌘⌫', '', 'chip--dlg') + chip('Cancel', '', '', 'chip--dlg') + chip('Save', '↩', '', 'chip--def') + '</div></div>' +
      '<div class="row" style="gap:8px"><b style="font:600 22px/1 var(--f-disp);letter-spacing:-.4px;flex:1">Xcode</b><span class="pillbtn">' + ic('pin') + '</span><span class="pillbtn">Edit</span></div>' +
      deck(XCODE_KEYS, 3, 10) + '<div class="pg"><i class="on"></i><i></i><i></i></div></div></div>' + home('pad') + '</div>';
    return phone(1180, 820, t, inner, { frame: 'ipad' });
  };

  /* iPad portrait (820 x 1180) */
  S.padPort = function (t) {
    var inner = '<div class="col">' + sb('pad') + header({ trailing: ['camera', 'sidebar', 'more'] }).replace('class="hdr"', 'class="hdr" style="padding:0 18px"') +
      '<div class="mir" style="margin:4px 18px 0;height:490px;border-radius:26px;flex:none">' + mac({ cur: [44, 40] }) + '<div class="mir__live"><i></i>LIVE</div>' +
      '<div class="mtool glass on-navy" style="position:absolute;left:50%;bottom:12px;translate:-50% 0"><span class="on">' + ic('pointer') + 'Direct</span><span>' + ic('zoom') + '</span><span>' + ic('keyboard') + '</span><span>' + ic('pip') + '</span><span>' + ic('expand') + '</span></div></div>' +
      '<div class="grow" style="display:flex;gap:14px;padding:14px 18px 0">' + pad({ style: 'margin:0', clicks: true, lit: [[200, 160, 60, 1]] }) +
      '<div style="width:300px;flex:none;display:flex;flex-direction:column;gap:10px"><div class="row" style="gap:8px">' + app('xcode', 'sm') + '<b style="font:600 20px/1 var(--f-disp);flex:1">Xcode</b><span class="pillbtn">Edit</span></div>' + deck(XCODE_KEYS.slice(0, 9), 3, 8) + '<div class="pg"><i class="on"></i><i></i><i></i></div></div></div>' +
      strip('app', { style: 'margin-top:10px;padding:6px 18px' }) +
      '<div class="row" style="gap:12px;padding:6px 18px 0">' + appDock({ style: 'flex:1;margin:0', apps: ['xcode', 'safari', 'terminal', 'figma', 'music', 'messages', 'notes', 'mail', 'finder'] }) + '<span class="ask glass" style="width:58px;height:58px"><span class="dotask"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span></span></div>' + home('pad') + '</div>';
    return phone(820, 1180, t, inner, { frame: 'ipad' });
  };

  /* iPad half Split View window (590 x 820) */
  S.padSplit = function (t) {
    var inner = '<div class="col">' + sb('pad') + header() +
      pad({ style: 'margin:0 14px', mirror: 'right:12px;top:12px;width:190px;height:119px', clicks: true, lit: [[180, 240, 60, 1]], cls: 'grow' }) +
      '<div style="height:250px;flex:none;padding:12px 14px 0;display:flex;flex-direction:column;gap:8px"><div class="row" style="gap:8px">' + app('xcode', 'sm') + '<b style="font:600 18px/1 var(--f-disp);flex:1">Xcode</b><span class="pillbtn">Edit</span></div>' + deck(XCODE_KEYS.slice(0, 5), 5, 8) + '</div>' +
      strip('dialog') + surfaceDock('pointer', { style: 'padding:6px 14px 0' }) + home('pad') + '</div>';
    return phone(590, 820, t, inner, { frame: 'bare' });
  };

  /* PiP on the iPhone Home Screen */
  function hsGrid(cols, names) {
    var lbl = { safari: 'Safari', messages: 'Messages', music: 'Music', photos: 'Photos', mail: 'Mail', notes: 'Notes', figma: 'Sketch', terminal: 'Shell', finder: 'Files', pages: 'Pages', xcode: 'Builds', slack: 'Chat' };
    return '<div class="hs__grid" style="grid-template-columns:repeat(' + cols + ',1fr)">' + names.map(function (n) { return '<div>' + app(n, 'lg') + '<div class="hs__lbl">' + (lbl[n] || n) + '</div></div>'; }).join('') + '</div>';
  }
  S.pipPhone = function () {
    var inner = '<div class="col hs">' + sb('pro', '#fff') + '<div style="padding:24px 22px 0">' + hsGrid(4, ['safari', 'messages', 'music', 'photos', 'mail', 'notes', 'figma', 'terminal', 'finder', 'pages', 'xcode', 'slack']) + '</div>' +
      '<div class="pip" style="left:16px;top:470px;width:250px;height:156px">' + mac({ dlg: true, cur: [52, 44] }) + '<div class="pip__top">' + ic('expand') + ic('x') + '</div><div class="pip__ctl">' + ic('pause') + '</div></div>' +
      '<span class="grow"></span><div style="margin:0 12px 10px;height:92px;border-radius:34px;background:rgba(255,255,255,.28);display:flex;align-items:center;justify-content:space-around">' + app('safari', 'lg') + app('messages', 'lg') + app('music', 'lg') + app('mail', 'lg') + '</div>' + home('pro', '#fff') + '</div>';
    return phone(402, 874, 'dark', inner);
  };
  S.pipPad = function () {
    var inner = '<div class="col" style="background:#f6f4ee;color:#1d1d1f">' + sb('pad', '#1d1d1f') + '<div class="row" style="padding:10px 26px;gap:14px"><b style="font:700 28px/1 var(--f-ui)">Notes</b></div>' +
      '<div style="padding:4px 26px;display:flex;flex-direction:column;gap:12px;max-width:640px">' + ['86%', '92%', '70%', '88%', '40%', '0', '80%', '90%', '62%'].map(function (w) { return '<i style="display:block;height:12px;width:' + w + ';border-radius:3px;background:#d8d4ca"></i>'; }).join('') + '</div>' +
      '<div class="pip" style="right:24px;top:70px;width:400px;height:250px">' + mac({ dlg: true, cur: [52, 44] }) + '</div>' + '<span class="grow"></span>' + home('pad', '#1d1d1f') + '</div>';
    return phone(1180, 820, 'light', inner, { frame: 'ipad' });
  };

  /* Pairing (1.1) */
  S.pair = function () {
    var inner = '<div class="col brandbg">' + sb('pro', '#fff') +
      '<div style="padding:30px 28px 0;display:flex;flex-direction:column;align-items:center;gap:22px;text-align:center;position:relative">' + hand(66) +
      '<div><div style="font:500 30px/1.1 var(--f-disp);letter-spacing:-.8px">Pair with Studio</div><div style="margin-top:10px;font:400 16px/1.4 var(--f-ui);color:rgba(255,255,255,.7)">Type the 12-digit code shown on your Mac, or scan its QR code.</div></div>' +
      '<div style="padding:18px 16px;border-radius:22px;background:rgba(255,255,255,.05);box-shadow:inset 0 0 0 1px rgba(255,255,255,.1)">' + dmx('4821 0937 552', 11) + '</div>' +
      '<div style="font:500 13px/1.4 var(--f-ui);color:rgba(255,255,255,.6)">The last digit checks for typos. 1 digit to go.</div>' +
      '<div class="btns" style="width:100%;background:rgba(255,255,255,.1);color:#fff">' + '<span class="row" style="gap:8px">' + ic('camera') + 'Scan QR code</span></div></div>' +
      '<span class="grow"></span><div style="background:rgba(30,34,60,.92);padding:8px 6px 4px;display:grid;grid-template-columns:repeat(3,1fr);gap:7px">' +
      ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'].map(function (k) { return '<span style="height:47px;border-radius:9px;display:grid;place-items:center;font:400 25px/1 var(--f-ui);' + (k && k !== '⌫' ? 'background:rgba(255,255,255,.22)' : '') + '">' + k + '</span>'; }).join('') + '</div>' +
      '<div style="background:rgba(30,34,60,.92)">' + home('pro', '#fff') + '</div></div>';
    return phone(402, 874, 'dark', inner);
  };

  /* Paywall */
  S.paywall = function () {
    function f(g, t, s) { return '<div class="row" style="gap:12px;align-items:flex-start"><span style="width:30px;height:30px;border-radius:9px;background:rgba(84,102,255,.22);display:grid;place-items:center;flex:none;color:#cfe0ff">' + ic(g).replace('<svg', '<svg style="width:17px;height:17px"') + '</span><span><b style="font:600 15px/1.25 var(--f-ui)">' + t + '</b><span style="display:block;font:400 13px/1.35 var(--f-ui);color:rgba(255,255,255,.62)">' + s + '</span></span></div>'; }
    var inner = '<div class="col brandbg">' + sb('pro', '#fff') + '<div class="row" style="padding:0 16px"><span class="grow"></span><span class="circ" style="background:rgba(255,255,255,.1);color:#fff;width:34px;height:34px">' + ic('x').replace('<svg', '<svg style="width:15px;height:15px"') + '</span></div>' +
      '<div style="padding:0 24px;display:flex;flex-direction:column;gap:18px;position:relative">' +
      '<div><span class="badge badge--pro">PRO</span><div style="margin-top:12px;font:500 32px/1.08 var(--f-disp);letter-spacing:-.9px">Everything your Mac can do, in your hand.</div></div>' +
      f('deck', 'Decks and app chips', 'Keys and chips built from each app’s real menus.') + f('screen', 'Live screen, PiP and capture', 'Watch, tap and read text from your Mac.') + f('imac', 'Every Mac you own', 'Switch with a swipe, run on several at once.') + f('share', 'Send between your devices', 'Clipboard, files, photos and links.') +
      '<div style="display:flex;flex-direction:column;gap:10px;margin-top:2px">' +
      '<div class="plan-card sel"><span class="radio"></span><span style="flex:1"><b style="font:600 16px/1.2 var(--f-ui)">Yearly</b><span style="display:block;font:400 13px/1.3 var(--f-ui);color:rgba(255,255,255,.65)">$19.99 per year after the free trial</span></span><span class="badge" style="background:rgba(61,224,176,.16);color:#3de0b0">Save 44%</span></div>' +
      '<div class="plan-card"><span class="radio"></span><span style="flex:1"><b style="font:600 16px/1.2 var(--f-ui)">Monthly</b><span style="display:block;font:400 13px/1.3 var(--f-ui);color:rgba(255,255,255,.65)">$2.99 per month after the free trial</span></span></div></div>' +
      '<div class="btnp">Try 2 weeks free</div>' +
      '<div style="font:400 11px/1.45 var(--f-ui);color:rgba(255,255,255,.55);text-align:center">Free for 2 weeks, then $19.99 a year. Renews automatically until you cancel at least 24 hours before the period ends. Manage it in Settings › Apple Account › Subscriptions.<br><u>Terms of Use</u> · <u>Privacy Policy</u> · <u>Restore Purchases</u></div>' +
      '<div style="font:500 12.5px/1.4 var(--f-ui);color:rgba(255,255,255,.7);text-align:center">Free forever: trackpad, keyboard and media keys for one Mac.</div></div>' +
      '<span class="grow"></span>' + home('pro', '#fff') + '</div>';
    return phone(402, 874, 'dark', inner);
  };

  /* Free tier: Deck surface as a locked preview */
  S.locked = function (t) {
    var keys = XCODE_KEYS.slice(0, 8).map(function (k) { return Object.assign({}, k, { s: null }); });
    var inner = '<div class="col">' + sb('pro') + header({ sub: 'Music' }) +
      '<div class="grow" style="position:relative;padding:6px 16px 0"><div style="filter:saturate(.4);opacity:.45;pointer-events:none">' + deck(keys, 4) + '</div>' +
      '<div style="position:absolute;left:16px;right:16px;top:120px;padding:22px;border-radius:26px;background:var(--elevated);box-shadow:0 20px 50px -12px rgba(6,10,42,.35), inset 0 0 0 .5px var(--hair);display:flex;flex-direction:column;gap:12px;align-items:flex-start">' +
      '<span class="badge badge--pro">PRO</span><b style="font:500 22px/1.15 var(--f-disp);letter-spacing:-.4px">Decks follow the app in front</b><span style="font:400 15px/1.4 var(--f-ui);color:var(--ink2)">Keys for Music, Xcode and every other app, built from their real menus. Try every Pro feature free for 2 weeks.</span>' +
      '<div class="row" style="gap:8px;width:100%"><span class="pillbtn pillbtn--accent" style="height:44px;padding:0 18px;font-size:15px">Try 2 weeks free</span><span class="pillbtn" style="height:44px">Not now</span></div></div></div>' +
      strip('free', { style: 'margin-top:8px' }) + appDock({ front: 'music' }) + surfaceDock('deck', { style: 'padding-top:10px' }) + home('pro') + '</div>';
    return phone(402, 874, t, inner);
  };

  /* Sharing: Send sheet + transfer beam */
  S.send = function (t) {
    var base = S.phPointer(t, { strip: 'app' }).html.replace(/^<div class="ph [^"]*" style="[^"]*">/, '').replace(/<\/div>$/, '');
    function dev(g, n, s, sel) { return '<div style="display:flex;flex-direction:column;align-items:center;gap:6px;width:78px"><span style="width:62px;height:62px;border-radius:20px;display:grid;place-items:center;background:' + (sel ? 'var(--accent)' : 'var(--fill)') + ';color:' + (sel ? '#fff' : 'var(--ink)') + '">' + ic(g).replace('<svg', '<svg style="width:28px;height:28px;stroke-width:1.5"') + '</span><b style="font:600 13px/1.1 var(--f-ui);text-align:center">' + n + '</b><small style="font:400 11px/1 var(--f-ui);color:var(--ink2)">' + s + '</small></div>'; }
    var sheet = '<div class="scrim"></div><div class="sheet-ui" style="height:560px"><div class="grab"></div><div class="sheet-ui__h"><h6>Send 3 photos</h6><span class="pillbtn">Cancel</span></div>' +
      '<div class="row" style="gap:10px;padding:8px 16px 0"><span style="width:74px;height:74px;border-radius:16px;background:linear-gradient(135deg,#86b4ff,#3a4cf2)"></span><span style="width:74px;height:74px;border-radius:16px;background:linear-gradient(135deg,#ffd2a1,#f06a1d)"></span><span style="width:74px;height:74px;border-radius:16px;background:linear-gradient(135deg,#a7f0d8,#0b8a7a)"></span><span style="font:500 13px/1.3 var(--f-ui);color:var(--ink2)">HEIC · 9.4 MB<br>Kept as is</span></div>' +
      '<div class="lbl" style="margin-top:18px">To</div><div class="row" style="gap:6px;padding:10px 12px 0;justify-content:space-between">' + dev('imac', 'Studio', 'Mac · online', 1) + dev('laptop', 'MacBook Air', 'Mac · online') + dev('ipad', 'iPad Pro', 'Open now') + dev('mini', 'Mac mini', 'Locked') + '</div>' +
      '<div style="margin:18px 16px 0;padding:14px;border-radius:18px;background:var(--fill);display:flex;flex-direction:column;gap:10px"><div class="row" style="gap:10px"><span class="circ circ--sm" style="background:var(--raised)">' + ic('iphone') + '</span><span class="beam grow" style="justify-content:space-between">' + '<i class="ok"></i><i class="ok"></i><i class="ok"></i><i class="ok"></i><i class="ok"></i><i class="on"></i><i class="on"></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i>' + '</span><span class="circ circ--sm" style="background:var(--raised)">' + ic('imac') + '</span></div><div class="row" style="font:500 13px/1 var(--f-ui);color:var(--ink2)"><span class="grow">Sending to Studio · 4.1 of 9.4 MB</span><span>Lands in Downloads › Pixel Hand</span></div></div>' +
      '<div style="padding:16px 16px 0"><div class="btnp">Send to Studio</div></div></div>';
    return phone(402, 874, t, base + sheet);
  };

  /* Deck editor: edit mode + key inspector with the 8x8 glyph editor */
  S.deckEdit = function (t) {
    var keys = XCODE_KEYS.slice(0, 8).map(function (k, i) { return Object.assign({}, k, { edit: 1, s: null, px: i === 1 ? GLYPH_ROCKET : null }); });
    var big = '<span class="px8" style="width:150px;height:150px;gap:3px;flex:none">';
    var rows = ['...##...', '..####..', '..#..#..', '..####..', '.######.', '.##..##.', '...##...', '..#..#..'];
    rows.forEach(function (r) { for (var i = 0; i < 8; i++) big += '<i style="border-radius:5px;background:' + (r[i] === '#' ? 'var(--accent)' : 'var(--fill)') + '"></i>'; });
    big += '</span>';
    var inner = '<div class="col">' + sb('pro') + '<div class="hdr"><span class="pillbtn">' + ic('undo') + 'Undo</span><span class="grow" style="text-align:center;font:600 17px/1 var(--f-ui)">Edit “Xcode”</span><span class="pillbtn pillbtn--accent">Done</span></div>' +
      '<div style="padding:8px 16px 0">' + deck(keys.concat([{ g: 'plus', l: 'Add key', ghost: 1 }]), 4) + '</div>' +
      '<div class="scrim" style="top:auto;height:0"></div>' +
      '<div class="sheet-ui" style="height:470px"><div class="grab"></div><div class="sheet-ui__h"><h6>Run key</h6><span class="pillbtn">' + ic('trash') + '</span></div>' +
      '<div class="row" style="gap:16px;padding:6px 16px 0;align-items:flex-start">' + big + '<div style="display:flex;flex-direction:column;gap:10px;flex:1;min-width:0">' +
      '<div class="lbl" style="padding:0">Label</div><div class="field" style="height:42px;font-size:16px">Run</div>' +
      '<div class="lbl" style="padding:0">Glyph</div><div class="row" style="gap:6px"><span class="pillbtn">Symbol</span><span class="pillbtn">App</span><span class="pillbtn pillbtn--tint">Pixels</span></div>' +
      '<div class="lbl" style="padding:0">Colour</div><div class="row" style="gap:8px"><i style="width:22px;height:22px;border-radius:7px;background:#3a4cf2;box-shadow:0 0 0 2px var(--elevated),0 0 0 4px #3a4cf2"></i><i style="width:22px;height:22px;border-radius:7px;background:#060a2a"></i><i style="width:22px;height:22px;border-radius:7px;background:#0b7a6c"></i><i style="width:22px;height:22px;border-radius:7px;background:#8e70ff"></i><i style="width:22px;height:22px;border-radius:7px;background:#3de0e0"></i></div></div></div>' +
      '<div class="list" style="margin-top:16px"><div class="li"><span class="li__t">Action<small>Menu › Product › Run (⌘R)</small></span>' + ic('chevR') + '</div><div class="li"><span class="li__t">Ask before running</span><span class="tog"></span></div><div class="li"><span class="li__t">Only on Studio</span><span class="tog on"></span></div></div></div></div>';
    return phone(402, 874, t, inner);
  };

  /* Empty / error state: Mac not reachable + permission pill */
  S.empty = function (t) {
    var inner = '<div class="col">' + sb('pro') + header({ sub: 'Not reachable', off: 1 }) +
      '<div style="padding:4px 14px 0"><div class="spill spill--warn">' + ic('warn') + '<span><b>Accessibility is off on Studio.</b> Clicks and keys won’t reach it.</span><span class="spill__fix">Fix</span></div></div>' +
      '<div class="pad grow" style="margin:12px 12px 0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;text-align:center;padding:24px">' +
      '<span style="opacity:.32;filter:grayscale(1)">' + hand(54) + '</span>' +
      '<b style="font:500 22px/1.2 var(--f-disp);color:#fff">Studio isn’t answering</b><span style="font:400 15px/1.4 var(--f-ui);color:rgba(255,255,255,.66);max-width:280px">It was last seen 2 minutes ago. Check these, then try again.</span>' +
      '<div style="display:flex;flex-direction:column;gap:8px;text-align:left;font:500 14px/1.3 var(--f-ui);color:rgba(255,255,255,.82)"><span class="row" style="gap:8px"><span class="ldot"></span>iPhone is on Wi-Fi “Home”</span><span class="row" style="gap:8px"><span class="ldot off"></span>Pixel Hand is open on Studio</span><span class="row" style="gap:8px"><span class="ldot off"></span>Studio is awake</span></div>' +
      '<div class="row" style="gap:8px;margin-top:6px"><span class="pillbtn pillbtn--accent" style="height:44px;padding:0 18px;font-size:15px">Try again</span><span class="pillbtn" style="height:44px;background:rgba(255,255,255,.1);color:#fff">Wake Studio</span></div></div>' +
      '<div style="height:10px"></div>' + surfaceDock('pointer', { style: 'padding-top:6px' }) + home('pro') + '</div>';
    return phone(402, 874, t, inner);
  };

  /* Mac menu-bar panel (340pt) */
  S.macPanel = function (t) {
    var inner = '<div class="mpanel"><div class="mpanel__h"><span class="mpanel__logo">' + hand(18) + '</span><span class="mrow__t"><b style="font-size:14px">Studio</b><small>2 devices connected · ready</small></span><span class="ldot"></span></div>' +
      '<div class="mpanel__div"></div><div class="mpanel__sec"><span class="mpanel__lbl">DEVICES</span>' +
      '<div class="mrow"><span class="circ circ--sm" style="background:var(--fill)">' + ic('iphone') + '</span><span class="mrow__t"><b>Sam’s iPhone</b><small>Controlling now · paired</small></span><span class="mbtn">Disconnect</span></div>' +
      '<div class="mcap"><span class="on">Control</span><span class="on">Screen</span><span class="on">Clipboard</span><span>Files: ask</span></div>' +
      '<div class="mrow" style="margin-top:4px"><span class="circ circ--sm" style="background:var(--fill)">' + ic('ipad') + '</span><span class="mrow__t"><b>iPad Pro</b><small>Glancing · paired</small></span><span class="mbtn">Disconnect</span></div>' +
      '<div class="mrow" style="margin-top:4px"><span class="mbtn mbtn--p">Pair a device…</span><span class="mbtn">Show code</span></div></div>' +
      '<div class="mpanel__div"></div><div class="mpanel__sec"><span class="mpanel__lbl">PERMISSIONS</span>' +
      '<div class="mrow"><span class="ldot"></span><span class="mrow__t"><b>Accessibility</b></span><small style="color:var(--mint)">On</small></div>' +
      '<div class="mrow"><span class="ldot"></span><span class="mrow__t"><b>Screen Recording</b></span><small style="color:var(--mint)">On</small></div>' +
      '<div class="mrow"><span class="ldot warn"></span><span class="mrow__t"><b>Notifications</b><small>Needed to accept files</small></span><span class="mbtn">Turn On…</span></div></div>' +
      '<div class="mpanel__div"></div><div class="mpanel__sec" style="padding-bottom:14px"><div class="mrow"><span class="mrow__t"><b>Open at login</b></span><span class="tog on" style="transform:scale(.7);transform-origin:right"></span></div><div class="mrow"><span class="mrow__t"><small>Version 1.0 (42) · Up to date</small></span><span class="mbtn">Settings…</span><span class="mbtn">Quit</span></div></div></div>';
    return { w: 340, h: 470, frame: 'bare', html: '<div class="ph ' + t + '" style="width:340px;height:470px;background:' + (t === 'dark' ? 'linear-gradient(160deg,#1b2a7a,#060a2a)' : 'linear-gradient(160deg,#c6dcff,#86b4ff)') + ';padding:0;border-radius:16px">' + inner + '</div>' };
  };

  /* Component sheet */
  S.components = function (t) {
    var inner = '<div style="padding:22px;display:flex;flex-direction:column;gap:18px">' +
      '<div class="lbl" style="padding:0">Chips: idle · sending · delivered · refused · dialog default · AI proposal</div>' +
      '<div class="row" style="gap:8px;flex-wrap:wrap">' + chip('Save', '⌘S') + chip('Run', '⌘R', 'send') + chip('Build', '⌘B', 'ok') + chip('Quit', '⌘Q', 'no') + chip('Save', '↩', '', 'chip--def') + '<span class="chip chip--ai"><span class="chip__l">+ Suggest</span></span></div>' +
      '<div class="lbl" style="padding:0">Deck keys: done · sending · ask first · system · AI ghost · editing</div>' +
      deck([{ g: 'hammer', l: 'Build', k: '⌘B', s: 'ok' }, { g: 'run', l: 'Run', k: '⌘R', s: 'send' }, { g: 'trash', l: 'Clean Build', k: '⇧⌘K', ask: 1 }, { g: 'mission', l: 'Mission Control', navy: 1 }, { g: 'doc', l: 'Minimap', ghost: 1 }, { g: 'stop', l: 'Stop', edit: 1, px: GLYPH_ROCKET }], 6, 10) +
      '<div class="lbl" style="padding:0">Dock, surfaces and Ask</div>' + appDock({ style: 'margin:0' }) + surfaceDock('pointer', { style: 'padding:0' }) +
      '<div class="lbl" style="padding:0">Toasts, status pill, progress beam</div>' +
      '<div class="row" style="gap:10px;flex-wrap:wrap"><span class="toast glass"><i></i>Build sent to Studio</span><span class="toast glass toast--no"><i></i>Quit refused: Accessibility is off</span></div>' +
      '<div class="spill spill--warn">' + ic('lock') + '<span><b>Studio is locked.</b> Type the password to unlock.</span><span class="spill__fix">Keyboard</span></div>' +
      '<div class="row" style="gap:14px"><span class="beam"><i class="ok"></i><i class="ok"></i><i class="ok"></i><i class="on"></i><i class="on"></i><i></i><i></i><i></i><i></i><i></i></span><span style="font:500 13px/1 var(--f-ui);color:var(--ink2)">Pairing, transfers and AI thinking use the dot beam, never a spinner.</span></div></div>';
    return { w: 600, h: 640, frame: 'bare', html: '<div class="ph ' + t + '" style="width:600px;height:640px">' + inner + '</div>' };
  };

  /* ---------- Render ---------- */
  var FRAME = { iphone: 'dev', se: 'dev dev--se', land: 'dev dev--land', ipad: 'dev dev--ipad', fold: 'dev dev--fold', bare: 'dev dev--bare' };
  var PADS = { iphone: [12, 12], se: [14, 64], land: [12, 12], ipad: [18, 18], fold: [11, 11], bare: [0, 0] };

  function fit() {
    document.querySelectorAll('.board').forEach(function (b) {
      var stage = b.querySelector('.stage'), dev = b.querySelector('.dev');
      if (!stage || !dev) return;
      var natural = Number(dev.dataset.ow);
      var target = Number(b.dataset.target || 300);
      var avail = b.parentElement.clientWidth;
      var z = Math.min(target, avail) / natural;
      dev.style.zoom = z.toFixed(4);
    });
  }

  function render() {
    document.querySelectorAll('.board[data-s]').forEach(function (b) {
      var fn = S[b.dataset.s];
      if (!fn) return;
      var r = fn(b.dataset.t || 'dark');
      var p = PADS[r.frame] || [12, 12];
      var ow = r.w + 2 * p[0];
      var cap = '<div class="board__cap"><b>' + (b.dataset.title || '') + '</b>' + (b.dataset.size ? '<code>' + b.dataset.size + '</code>' : '') + (b.dataset.note ? '<span>' + b.dataset.note + '</span>' : '') + '</div>';
      b.innerHTML = '<div class="stage"><div class="' + FRAME[r.frame] + '" data-ow="' + ow + '" role="img" aria-label="' + (b.dataset.title || 'Mockup') + '">' + r.html + '</div></div>' + cap;
      if (r.w > r.h * 1.1 || r.w > 700) b.classList.add('board--wide');
    });
    fit();
  }

  /* Tap a mockup to see it larger (useful for iPad boards on a phone). */
  var box = null;
  function closeBox() { if (box) { box.remove(); box = null; document.body.style.overflow = ''; } }
  function openBox(dev) {
    closeBox();
    box = document.createElement('div');
    box.className = 'lightbox';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-label', 'Enlarged mockup');
    var copy = dev.cloneNode(true);
    var natural = Number(dev.dataset.ow);
    var z = Math.min(1, (window.innerWidth - 24) / natural);
    if (natural < 700) z = Math.min(1.25, (window.innerHeight - 96) / (dev.offsetHeight / Number(dev.style.zoom || 1)), (window.innerWidth - 24) / natural);
    copy.style.zoom = z.toFixed(4);
    var close = document.createElement('button');
    close.className = 'lightbox__x';
    close.type = 'button';
    close.textContent = 'Close';
    close.addEventListener('click', closeBox);
    var inner = document.createElement('div');
    inner.className = 'lightbox__in';
    inner.appendChild(copy);
    box.appendChild(close);
    box.appendChild(inner);
    box.addEventListener('click', function (e) { if (e.target === box || e.target === inner) closeBox(); });
    document.body.appendChild(box);
    document.body.style.overflow = 'hidden';
    close.focus();
  }
  document.addEventListener('click', function (e) {
    var dev = e.target.closest && e.target.closest('.board .dev');
    if (dev && !box) openBox(dev);
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeBox(); });

  window.addEventListener('resize', function () { window.requestAnimationFrame(fit); });

  /* Parts shared with pixel.js, which adds the round-2 screens before render. */
  window.PH = { S: S, P: P, ic: ic, app: app, mac: mac, lit: lit, pad: pad, macpill: macpill, header: header, chip: chip, strip: strip,
    appDock: appDock, surfaceDock: surfaceDock, key: key, deck: deck, dmx: dmx, hand: hand, phone: phone, sb: sb, home: home, XCODE_KEYS: XCODE_KEYS, fit: fit };
  function start() { setTimeout(render, 0); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
