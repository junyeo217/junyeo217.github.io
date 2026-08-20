(function () {
  'use strict';

  var root = document.documentElement;
  var body = document.body;
  var views = Array.prototype.slice.call(document.querySelectorAll('[data-view]'));
  var links = Array.prototype.slice.call(document.querySelectorAll('[data-view-link]'));
  var valid = { home: true, works: true, about: true, contact: true };
  var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  var activeView = '';

  function viewFromLocation() {
    var name = location.hash.replace(/^#/, '').toLowerCase();
    return valid[name] ? name : 'home';
  }

  function locationMatches(name) {
    var hash = location.hash.replace(/^#/, '').toLowerCase();
    if (name === 'home') return hash === '' || hash === 'home';
    return hash === name;
  }

  function syncMedia(name) {
    document.querySelectorAll('video').forEach(function (video) {
      var panel = video.closest('[data-view]');
      if (panel && panel.getAttribute('data-view') !== name) video.pause();
    });

    if (name === 'home') {
      var hero = document.querySelector('.hero-video');
      if (hero) {
        if (reducedMotion.matches) {
          hero.pause();
          return;
        }
        hero.muted = true;
        hero.playsInline = true;
        var play = hero.play();
        if (play && play.catch) play.catch(function () {});
      }
    }
  }

  function activateView(name, push) {
    if (!valid[name]) name = 'home';

    views.forEach(function (view) {
      var on = view.getAttribute('data-view') === name;
      view.hidden = !on;
      view.classList.toggle('is-active', on);
      view.setAttribute('aria-hidden', on ? 'false' : 'true');
      if (on) {
        var scroller = view.querySelector('.view-scroll');
        if (scroller) scroller.scrollTop = 0;
      }
    });

    links.forEach(function (link) {
      if (link.getAttribute('data-view-link') === name) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
    });

    body.setAttribute('data-active-view', name);
    activeView = name;
    syncMedia(name);

    if (push) {
      var target = name === 'home'
        ? location.pathname + location.search
        : location.pathname + location.search + '#' + name;
      history.pushState({ view: name }, '', target);
    }
  }

  links.forEach(function (link) {
    link.addEventListener('click', function (event) {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      var name = link.getAttribute('data-view-link');
      activateView(name, name !== activeView || !locationMatches(name));
    });
  });

  var skipLink = document.querySelector('.skip-link');
  if (skipLink) {
    skipLink.addEventListener('click', function (event) {
      event.preventDefault();
      var main = document.getElementById('main');
      if (main) main.focus();
    });
  }

  window.addEventListener('popstate', function () { activateView(viewFromLocation(), false); });
  window.addEventListener('hashchange', function () { activateView(viewFromLocation(), false); });
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) document.querySelectorAll('video').forEach(function (video) { video.pause(); });
    else syncMedia(activeView);
  });
  if (reducedMotion.addEventListener) {
    reducedMotion.addEventListener('change', function () { syncMedia(activeView); });
  }

  activateView(viewFromLocation(), false);
  window.__portfolioViews = { activate: function (name) { activateView(name, true); }, current: function () { return activeView; } };

  var intro = document.getElementById('intro');
  if (!intro || !root.classList.contains('intro-pending')) return;

  var introLines = Array.prototype.slice.call(intro.querySelectorAll('[data-intro-text]'));
  var introTimers = [];
  var finished = false;
  var timing = {
    start: 120,
    lineGap: 170,
    hold: 420,
    fade: 430,
    hardCap: 3300
  };

  function later(fn, delay) {
    var timer = window.setTimeout(function () {
      if (!finished) fn();
    }, delay);
    introTimers.push(timer);
    return timer;
  }

  function clearIntroTimers() {
    introTimers.forEach(function (timer) { window.clearTimeout(timer); });
    introTimers.length = 0;
  }

  function finishIntro() {
    if (finished) return;
    finished = true;
    clearIntroTimers();
    document.removeEventListener('keydown', finishIntro, true);
    intro.removeEventListener('pointerdown', finishIntro);
    intro.classList.add('is-out');
    window.setTimeout(function () {
      root.classList.remove('intro-pending');
      intro.classList.remove('is-visible', 'is-out');
      introLines.forEach(function (line) { line.classList.remove('is-typing'); });
      syncMedia(activeView);
    }, timing.fade);
  }

  function keyDelay(character, index) {
    if (character === ' ') return 45;
    if (character === ',' || character === '.') return 150;
    return 68 + (index % 3) * 9;
  }

  function typeLine(lineIndex) {
    if (lineIndex >= introLines.length) {
      later(finishIntro, timing.hold);
      return;
    }

    var line = introLines[lineIndex];
    var output = line.querySelector('.intro-text');
    var characters = Array.from(line.getAttribute('data-intro-text') || '');
    var index = 0;
    if (!output) {
      finishIntro();
      return;
    }

    line.classList.add('is-typing');
    output.textContent = '';

    (function typeNext() {
      if (index >= characters.length) {
        if (lineIndex < introLines.length - 1) {
          line.classList.remove('is-typing');
          later(function () { typeLine(lineIndex + 1); }, timing.lineGap);
        } else {
          later(finishIntro, timing.hold);
        }
        return;
      }

      var character = characters[index];
      output.textContent += character;
      index += 1;
      later(typeNext, keyDelay(character, index));
    })();
  }

  intro.addEventListener('pointerdown', finishIntro);
  document.addEventListener('keydown', finishIntro, true);
  window.requestAnimationFrame(function () {
    window.requestAnimationFrame(function () { intro.classList.add('is-visible'); });
  });
  later(function () { typeLine(0); }, timing.start);
  later(finishIntro, timing.hardCap);
})();
