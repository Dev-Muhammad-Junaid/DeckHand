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

  // Hero dot screen: a faint grid of pixels that lights up around the pointer.
  var canvas = document.querySelector('.hero__pixels');
  if (canvas && canvas.getContext) {
    var ctx = canvas.getContext('2d');
    var hero = canvas.parentNode;
    var PITCH = 16, DOT = 2.4, RADIUS = 150;
    var dpr = 1, w = 0, h = 0, pointer = null, glow = 0, frame = 0;
    var canHover = window.matchMedia('(hover: hover) and (pointer: fine)').matches && !reduce;

    function size() {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      w = hero.clientWidth; h = hero.clientHeight;
      canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
      draw();
    }
    function draw() {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      var ox = (w % PITCH) / 2, oy = 6;
      for (var y = oy; y < h; y += PITCH) {
        for (var x = ox; x < w; x += PITCH) {
          var a = 0.07, lit = 0;
          if (pointer && glow > 0) {
            var dx = x - pointer.x, dy = y - pointer.y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < RADIUS) lit = Math.pow(1 - dist / RADIUS, 1.6) * glow;
          }
          if (lit > 0.01) {
            ctx.fillStyle = 'rgba(190, 240, 255,' + (a + lit * 0.6).toFixed(3) + ')';
            var s = DOT + lit * 2.2;
            ctx.fillRect(x - s / 2, y - s / 2, s, s);
          } else {
            ctx.fillStyle = 'rgba(255, 255, 255,' + a + ')';
            ctx.fillRect(x - DOT / 2, y - DOT / 2, DOT, DOT);
          }
        }
      }
    }
    var last = null;
    function tick() {
      frame = 0;
      if (!pointer && glow > 0) {
        glow = Math.max(0, glow - 0.06);
        pointer = glow > 0 ? last : null;
        draw();
        pointer = null;
        if (glow > 0) frame = requestAnimationFrame(tick);
        return;
      }
      if (pointer) last = pointer;
      draw();
    }
    function schedule() { if (!frame) frame = requestAnimationFrame(tick); }

    size();
    window.addEventListener('resize', size);
    if (canHover) {
      hero.addEventListener('pointermove', function (e) {
        var r = hero.getBoundingClientRect();
        pointer = { x: e.clientX - r.left, y: e.clientY - r.top };
        glow = 1;
        schedule();
      });
      hero.addEventListener('pointerleave', function () { pointer = null; schedule(); });
    }
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
