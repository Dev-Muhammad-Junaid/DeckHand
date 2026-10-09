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

  // FAQ accordion.
  document.querySelectorAll('.faq__q').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var item = btn.closest('.faq__item');
      var open = item.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
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
