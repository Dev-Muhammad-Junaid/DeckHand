(function () {
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Split display headings into words that rise one after another.
  document.querySelectorAll('[data-words]').forEach(function (el) {
    var text = el.textContent.trim();
    var inHero = !!el.closest('.hero');
    el.setAttribute('aria-label', text);
    el.textContent = '';
    if (!inHero) el.classList.add('words');
    text.split(/\s+/).forEach(function (w, i, all) {
      var span = document.createElement('span');
      span.className = 'word';
      span.setAttribute('aria-hidden', 'true');
      span.style.setProperty('--wd', (i * 70 + (inHero ? 0 : 120)) + 'ms');
      span.textContent = w + (i < all.length - 1 ? ' ' : '');
      el.appendChild(span);
    });
  });

  // Reveal once, when 20% is in view.
  var targets = document.querySelectorAll('.reveal, .words');
  if (reduce || !('IntersectionObserver' in window)) {
    targets.forEach(function (el) { el.classList.add('is-in'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
      });
    }, { threshold: 0.2, rootMargin: '0px 0px -10% 0px' });
    targets.forEach(function (el) { io.observe(el); });
    // Never leave content hidden if the observer doesn't fire (print, previews).
    setTimeout(function () {
      targets.forEach(function (el) {
        var r = el.getBoundingClientRect();
        if (r.top < window.innerHeight && r.bottom > 0) el.classList.add('is-in');
      });
    }, 1500);
  }

  // Hero dot screen: the icon's dot grid behind the headline. On load the
  // pointing hand boots up in it, row by row from the fingertip, flicks its
  // tap rays on, then fades back into the grid as the headline arrives. After
  // that the dots light around a mouse pointer, or in a ring from a tap on a
  // touch screen. Frames are only drawn while something is changing.
  var canvas = document.querySelector('.hero__pixels');
  var root = document.documentElement;
  if (canvas && canvas.getContext) {
    var ctx = canvas.getContext('2d');
    var hero = canvas.parentNode;
    var PITCH = 16, DOT = 2.4, RADIUS = 150, RING_MS = 600;
    var dpr = 1, w = 0, h = 0, ox = 0, oy = 6;
    var canHover = !reduce && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
    var pointer = null, last = null, glow = 0, ring = null, frame = 0, lastT = 0;

    // The hand from the icon (DeckHand/Shared/PixelArt.swift): X is the lit
    // outline, o the violet fill. Rays are [column, row, far] relative to it.
    var HAND = [
      '.....XX..........', '....XooX.........', '....XooX.........', '....XooX.........',
      '....XooX.........', '....XooXXX.XX....', '....XooXooXooXX..', '....XooXooXooXoX.',
      '.XX.XooXooXooXoX.', 'XooXXooXooXooXoX.', 'XoooXooooooooooX.', '.XooXooooooooooX.',
      '..XoooooooooooX..', '..XoooooooooooX..', '...XooooooooooX..', '....XooooooooX...',
      '....XooooooooX...', '....XXXXXXXXXX...'
    ];
    var RAYS = [[5, -2, 0], [6, -2, 0], [3, -1, 0], [8, -1, 0], [5, -3, 1], [6, -3, 1], [2, -2, 1], [9, -2, 1]];
    // Timeline in ms: a row lights every ROW_MS from START, the rays flick on
    // at the end, and each row fades back over FADE_MS from HOLD. It plays
    // alongside the headline's own entrance; the copy never waits for it.
    var START = 60, ROW_MS = 34, RAYS_AT = 700, FAR_RAYS_AT = 770, HOLD = 850, FADE_MS = 800, FADE_STAGGER = 18;
    var BOOT_END = HOLD + FADE_STAGGER * HAND.length + FADE_MS;
    // The rays sit above the headline, so they can stay lit a moment longer.
    var RAYS_HOLD = HOLD + 160;
    var art = [];
    HAND.forEach(function (row, y) {
      for (var x = 0; x < row.length; x++) {
        var ch = row.charAt(x);
        // A little per-dot jitter so a row comes on like phosphor, not a wipe.
        if (ch !== '.') art.push({ c: x, r: y, kind: ch, on: START + y * ROW_MS + ((x * 7 + y * 3) % 5) * 9 });
      }
    });
    RAYS.forEach(function (p) { art.push({ c: p[0], r: p[1], kind: p[2] ? 'f' : 'r', on: p[2] ? FAR_RAYS_AT : RAYS_AT }); });

    var boot = null;
    var bootWanted = root.classList.contains('boot') && !reduce && !document.hidden &&
      !(location.hash && location.hash !== '#top') && window.scrollY < 200;
    if (bootWanted) boot = { started: false, t: 0, c0: 0, r0: 0 };
    else root.classList.remove('boot');
    function endBoot() { boot = null; root.classList.remove('boot'); }

    // The cyan bloom behind lit outline dots, rendered once.
    var halo = document.createElement('canvas');
    halo.width = halo.height = 64;
    (function () {
      var g = halo.getContext('2d');
      var grad = g.createRadialGradient(32, 32, 0, 32, 32, 32);
      grad.addColorStop(0, 'rgba(61, 224, 224, 0.75)');
      grad.addColorStop(0.35, 'rgba(61, 224, 224, 0.28)');
      grad.addColorStop(1, 'rgba(61, 224, 224, 0)');
      g.fillStyle = grad;
      g.fillRect(0, 0, 64, 64);
    })();

    function place() {
      // Centre the art (rays to wrist, 21 rows) on the headline and intro,
      // snapped to the grid and kept clear of the nav capsule.
      var inner = hero.querySelector('.hero__inner');
      var title = hero.querySelector('.hero__title');
      var desc = hero.querySelector('.hero__desc') || title;
      var nav = document.querySelector('.nav');
      var top = inner.offsetTop + title.offsetTop;
      var bottom = inner.offsetTop + desc.offsetTop + desc.offsetHeight;
      var navBottom = nav ? nav.offsetTop + nav.offsetHeight : 0;
      var r0 = Math.round(((top + bottom) / 2 - oy) / PITCH - 7);
      var minR0 = Math.ceil((navBottom + 10 - oy) / PITCH) + 3;
      boot.r0 = Math.max(r0, minR0);
      boot.c0 = Math.round((w / 2 - ox) / PITCH - 7.5);
      // The intro paragraph is small text; dots that pass under it stay dim
      // so it reads while the hand is lit. The headline is large enough not to.
      var pad = 8, dx = inner.offsetLeft + desc.offsetLeft, dy = inner.offsetTop + desc.offsetTop;
      boot.quiet = desc === title ? null : {
        x0: dx - pad, y0: dy - pad, x1: dx + desc.offsetWidth + pad, y1: dy + desc.offsetHeight + pad
      };
    }

    function size() {
      var nw = hero.clientWidth, nh = hero.clientHeight;
      var ndpr = Math.min(window.devicePixelRatio || 1, 2);
      if (nw === w && nh === h && ndpr === dpr) return;
      var widthChanged = nw !== w;
      dpr = ndpr; w = nw; h = nh;
      ox = (w % PITCH) / 2;
      canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
      if (boot && (widthChanged || !boot.started)) place();
      draw(performance.now());
    }

    // 0 → a brief flash above full → settles at 1, like a phosphor dot powering on.
    function powerOn(t) {
      if (t <= 0) return 0;
      if (t < 70) return 1.3 * t / 70;
      if (t < 230) return 1.3 - 0.3 * (t - 70) / 160;
      return 1;
    }
    // Rays flicker on: on, off, on.
    function flicker(t) {
      if (t <= 0) return 0;
      if (t < 45) return 1.2;
      if (t < 95) return 0.12;
      return t < 220 ? 1.15 : 1;
    }
    // Long-tailed fade: most of the light goes quickly, the rest lingers.
    function fadeOut(p) { return p <= 0 ? 1 : p >= 1 ? 0 : (1 - p) * (1 - p); }

    function dot(x, y, s) { ctx.rect(x - s / 2, y - s / 2, s, s); }
    function fillDot(x, y, s, style) {
      ctx.fillStyle = style;
      ctx.beginPath();
      if (ctx.roundRect) ctx.roundRect(x - s / 2, y - s / 2, s, s, s * 0.3); else dot(x, y, s);
      ctx.fill();
    }

    function draw(now) {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);

      // The resting grid, in one path.
      ctx.fillStyle = 'rgba(255, 255, 255, 0.07)';
      ctx.beginPath();
      for (var y = oy; y < h; y += PITCH) for (var x = ox; x < w; x += PITCH) dot(x, y, DOT);
      ctx.fill();

      // Live activity: the pointer's glow and a tap's ring, in ray cyan.
      var lit = {};
      function light(cx, cy, reach, fn) {
        var c0 = Math.max(0, Math.floor((cx - reach - ox) / PITCH)), c1 = Math.ceil((cx + reach - ox) / PITCH);
        var r0 = Math.max(0, Math.floor((cy - reach - oy) / PITCH)), r1 = Math.ceil((cy + reach - oy) / PITCH);
        for (var r = r0; r <= r1; r++) {
          for (var c = c0; c <= c1; c++) {
            var px = ox + c * PITCH, py = oy + r * PITCH;
            if (px > w || py > h) continue;
            var e = fn(Math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)));
            var k = r * 10000 + c;
            if (e > 0.01 && e > (lit[k] ? lit[k][2] : 0)) lit[k] = [px, py, e];
          }
        }
      }
      if (last && glow > 0) {
        light(last.x, last.y, RADIUS, function (d) { return d < RADIUS ? Math.pow(1 - d / RADIUS, 1.6) * glow : 0; });
      }
      if (ring) {
        var p = Math.max(0, Math.min(1, (now - ring.t0) / RING_MS));
        var radius = 12 + (1 - Math.pow(1 - p, 2)) * 150, band = 20, amp = Math.pow(1 - p, 1.4);
        light(ring.x, ring.y, radius + band, function (d) { return Math.max(0, 1 - Math.abs(d - radius) / band) * amp; });
      }
      for (var key in lit) {
        var l = lit[key];
        ctx.fillStyle = 'rgba(159, 246, 255,' + (0.07 + l[2] * 0.6).toFixed(3) + ')';
        ctx.beginPath(); dot(l[0], l[1], DOT + l[2] * 2.2); ctx.fill();
      }

      // The boot-up: the hand in phosphor and violet, then its rays.
      if (boot && boot.started) {
        var t = boot.t;
        for (var i = 0; i < art.length; i++) {
          var a = art[i];
          var isRay = a.kind === 'r' || a.kind === 'f';
          var k = isRay ? flicker(t - a.on) : powerOn(t - a.on);
          if (k <= 0) continue;
          var fadeAt = isRay ? RAYS_HOLD : HOLD + a.r * FADE_STAGGER;
          k *= fadeOut((t - fadeAt) / FADE_MS);
          if (k <= 0.004) continue;
          var px = ox + (boot.c0 + a.c) * PITCH, py = oy + (boot.r0 + a.r) * PITCH;
          var q = boot.quiet;
          if (q && px > q.x0 && px < q.x1 && py > q.y0 && py < q.y1) k *= 0.25;
          if (a.kind === 'o') {
            fillDot(px, py, DOT + 2.8 * Math.min(k, 1), 'rgba(142, 112, 255,' + Math.min(0.7, 0.07 + 0.58 * k).toFixed(3) + ')');
          } else {
            var strength = a.kind === 'f' ? 0.65 : 1;
            ctx.globalAlpha = Math.min(1, 0.42 * k * strength);
            ctx.drawImage(halo, px - 14, py - 14, 28, 28);
            ctx.globalAlpha = 1;
            var color = a.kind === 'X' ? '239, 255, 252' : '159, 246, 255';
            fillDot(px, py, DOT + 3 * Math.min(k, 1.15), 'rgba(' + color + ',' + Math.min(0.88, (0.07 + 0.74 * k) * strength).toFixed(3) + ')');
          }
        }
      }
    }

    function tick(now) {
      frame = 0;
      var dt = lastT ? now - lastT : 16;
      lastT = now;
      var busy = false;
      if (boot) {
        // The boot runs on its own clock that never jumps more than ~3 frames,
        // so a busy main thread during page load slows it instead of skipping rows.
        if (!boot.started) { boot.started = true; place(); } else boot.t += Math.min(dt, 50);
        // A long stall (the tab went to the background) ends it at the resting grid.
        if (dt > 1000 || boot.t > BOOT_END) endBoot(); else busy = true;
      }
      if (!pointer && glow > 0) { glow = Math.max(0, glow - dt / 280); if (glow > 0) busy = true; else last = null; }
      if (ring) { if (now - ring.t0 >= RING_MS) ring = null; else busy = true; }
      draw(now);
      if (busy) frame = requestAnimationFrame(tick); else lastT = 0;
    }
    function schedule() { if (!frame) frame = requestAnimationFrame(tick); }

    size();
    if ('ResizeObserver' in window) new ResizeObserver(size).observe(hero);
    else window.addEventListener('resize', size);
    if (boot) {
      schedule();
      document.addEventListener('visibilitychange', function () { if (document.hidden && boot) { endBoot(); schedule(); } });
    }

    if (canHover) {
      hero.addEventListener('pointermove', function (e) {
        if (e.pointerType !== 'mouse') return;
        var r = hero.getBoundingClientRect();
        pointer = last = { x: e.clientX - r.left, y: e.clientY - r.top };
        glow = 1;
        schedule();
      });
      hero.addEventListener('pointerleave', function () { pointer = null; schedule(); });
    }
    if (!reduce) {
      // Touch screens have no hover: a tap sends one ring of lit dots outward.
      hero.addEventListener('pointerdown', function (e) {
        if (e.pointerType === 'mouse') return;
        var r = hero.getBoundingClientRect();
        ring = { x: e.clientX - r.left, y: e.clientY - r.top, t0: performance.now() };
        schedule();
      }, { passive: true });
    }
  } else {
    root.classList.remove('boot');
  }

  // FAQ accordion.
  document.querySelectorAll('.faq__q').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var item = btn.closest('.faq__item');
      var open = item.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  });

  // Waitlist.
  var JOINED_KEY = 'deckhand.waitlist.joined';
  var joined = false;
  try { joined = localStorage.getItem(JOINED_KEY) === '1'; } catch (e) {}
  document.querySelectorAll('[data-waitlist]').forEach(function (form) {
    var input = form.querySelector('input[type=email]');
    var button = form.querySelector('button[type=submit]');
    var msg = form.querySelector('.wl__msg');
    var label = button.textContent;
    function say(text, isError) { msg.textContent = text; msg.classList.toggle('is-error', !!isError); }
    function done(text) { form.classList.add('is-done'); say(text); }
    if (joined) done('You’re on the list. We’ll email you when Deck Hand is ready.');

    form.addEventListener('submit', function (event) {
      event.preventDefault();
      var email = input.value.trim();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
        say('Enter an email address like you@example.com.', true);
        input.focus();
        return;
      }
      button.disabled = true;
      button.textContent = 'Joining…';
      say('');
      fetch(form.getAttribute('action'), {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email: email,
          company: form.querySelector('[name=company]').value,
          source: form.querySelector('[name=source]').value
        })
      }).then(function (res) {
        return res.json().catch(function () { return { ok: false }; });
      }).then(function (body) {
        if (body.ok) {
          try { localStorage.setItem(JOINED_KEY, '1'); } catch (e) {}
          done(body.already ? 'You’re already on the list. We’ll be in touch.' : 'You’re on the list. We’ll email you when Deck Hand is ready.');
        } else if (body.error === 'invalid_email') {
          say('That email doesn’t look right. Check it and try again.', true);
        } else {
          say('We couldn’t add you just now. Try again in a minute.', true);
        }
      }).catch(function () {
        say('We couldn’t reach the waitlist. Check your connection and try again.', true);
      }).then(function () {
        button.disabled = false;
        button.textContent = label;
      });
    });
  });

  // Copy build commands.
  document.querySelectorAll('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var text = btn.getAttribute('data-copy');
      var done = function () { btn.textContent = 'Copied'; setTimeout(function () { btn.textContent = 'Copy'; }, 1600); };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () { selectCode(btn); });
      } else { selectCode(btn); }
    });
  });
  function selectCode(btn) {
    var code = btn.parentNode.querySelector('code');
    var range = document.createRange();
    range.selectNodeContents(code);
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    btn.textContent = 'Press ⌘C';
  }
})();
