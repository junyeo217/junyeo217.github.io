(function () {
  'use strict';

  function toArray(list) {
    return Array.prototype.slice.call(list);
  }

  function initTabs(tablist) {
    var scope = tablist.closest('[data-higgs-tab-scope]') || document;
    var tabs = toArray(tablist.querySelectorAll('[role="tab"]'));
    var historyEnabled = scope.nodeType === 1 &&
      scope.getAttribute('data-higgs-history') === 'true';
    var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (!tabs.length) return null;

    function panelFor(tab) {
      var panelId = tab.getAttribute('aria-controls');
      return panelId ? scope.querySelector('#' + panelId) : null;
    }

    function enabledTabs() {
      return tabs.filter(function (tab) { return !tab.disabled; });
    }

    function tabFromHash() {
      if (!historyEnabled || !window.location.hash) return null;
      var value;
      try {
        value = decodeURIComponent(window.location.hash.slice(1));
      } catch (error) {
        if (error instanceof URIError) return null;
        throw error;
      }
      return tabs.find(function (tab) {
        return tab.getAttribute('data-tab-value') === value && !tab.disabled;
      }) || null;
    }

    function setHash(tab, replace) {
      if (!historyEnabled || !window.history) return;
      var value = tab.getAttribute('data-tab-value');
      if (!value) return;
      var nextHash = '#' + encodeURIComponent(value);
      if (window.location.hash === nextHash) return;
      var method = replace ? 'replaceState' : 'pushState';
      window.history[method](null, '', nextHash);
    }

    function activate(tab, options) {
      if (!tab || tab.disabled) return;
      options = options || {};

      tabs.forEach(function (candidate) {
        var selected = candidate === tab;
        var panel = panelFor(candidate);

        candidate.setAttribute('aria-selected', selected ? 'true' : 'false');
        candidate.setAttribute('tabindex', selected ? '0' : '-1');

        if (panel) {
          panel.hidden = !selected;
          panel.classList.toggle('is-active', selected);
          panel.setAttribute('data-active', selected ? 'true' : 'false');
        }
      });

      if (options.updateHash !== false) setHash(tab, options.replaceHash === true);
      if (options.focus === true) tab.focus({ preventScroll: true });

      if (options.scroll !== false && tab.scrollIntoView) {
        tab.scrollIntoView({
          behavior: reduceMotion ? 'auto' : 'smooth',
          block: 'nearest',
          inline: 'center'
        });
      }

      scope.dispatchEvent(new CustomEvent('higgs:tabchange', {
        bubbles: true,
        detail: { value: tab.getAttribute('data-tab-value') || '' }
      }));
    }

    function moveFrom(current, direction) {
      var available = enabledTabs();
      var index = available.indexOf(current);
      if (index < 0) index = 0;

      if (direction === 'home') return available[0];
      if (direction === 'end') return available[available.length - 1];

      var next = (index + direction + available.length) % available.length;
      return available[next];
    }

    tablist.addEventListener('click', function (event) {
      var tab = event.target.closest('[role="tab"]');
      if (!tab || !tablist.contains(tab) || tab.disabled) return;
      activate(tab, { focus: true });
    });

    tablist.addEventListener('keydown', function (event) {
      var tab = event.target.closest('[role="tab"]');
      if (!tab || !tablist.contains(tab)) return;

      var nextTab = null;
      if (event.key === 'ArrowRight') nextTab = moveFrom(tab, 1);
      if (event.key === 'ArrowLeft') nextTab = moveFrom(tab, -1);
      if (event.key === 'Home') nextTab = moveFrom(tab, 'home');
      if (event.key === 'End') nextTab = moveFrom(tab, 'end');

      if (!nextTab) return;
      event.preventDefault();
      activate(nextTab, { focus: true });
    });

    var defaultTab = tabs.find(function (tab) {
      return tab.getAttribute('aria-selected') === 'true' && !tab.disabled;
    }) || enabledTabs()[0];

    if (historyEnabled) {
      window.addEventListener('hashchange', function () {
        var hashed = tabFromHash();
        activate(hashed || defaultTab, { updateHash: false, focus: false });
      });
    }

    var initial = tabFromHash() || defaultTab;

    activate(initial, {
      updateHash: false,
      focus: false,
      scroll: false
    });

    if (initial.scrollIntoView) {
      initial.scrollIntoView({
        behavior: 'auto',
        block: 'nearest',
        inline: 'center'
      });
    }

    return {
      activate: activate,
      panels: tabs.map(panelFor).filter(Boolean),
      scope: scope,
      tabs: tabs
    };
  }

  function initSectionNav(controller) {
    var scope = controller.scope;
    var observer = null;
    var frame = null;
    var panel = null;
    var nav = null;
    var links = [];
    var targets = [];
    var usingScrollFallback = false;

    function activePanel() {
      return controller.panels.find(function (candidate) {
        return !candidate.hidden && candidate.getAttribute('data-active') === 'true';
      }) || null;
    }

    function targetFor(link) {
      var hash = link.getAttribute('href');
      var id;
      if (!hash || hash.charAt(0) !== '#') return null;
      try {
        id = decodeURIComponent(hash.slice(1));
      } catch (error) {
        return null;
      }
      var target = id ? document.getElementById(id) : null;
      return target && panel && panel.contains(target) ? target : null;
    }

    function activationLine() {
      var header = document.querySelector('.hd-header');
      var bottom = header ? header.getBoundingClientRect().bottom : 0;
      var rootStyle = window.getComputedStyle ? window.getComputedStyle(document.documentElement) : null;
      var offset = rootStyle ? parseFloat(rootStyle.getPropertyValue('--hd-space-4')) : 0;
      return Math.max(0, bottom) + (offset || 16) + 1;
    }

    function setCurrent(next) {
      links.forEach(function (link) {
        if (link === next) {
          link.setAttribute('aria-current', 'location');
        } else {
          link.removeAttribute('aria-current');
        }
      });
    }

    function updateCurrent() {
      var line = activationLine();
      var first = null;
      var current = null;
      targets.forEach(function (target, index) {
        if (!target) return;
        if (!first) first = links[index];
        if (target.getBoundingClientRect().top <= line) current = links[index];
      });
      setCurrent(current || first);
    }

    function scheduleUpdate() {
      if (frame !== null) return;
      var callback = function () {
        frame = null;
        updateCurrent();
      };
      frame = window.requestAnimationFrame ? window.requestAnimationFrame(callback) : window.setTimeout(callback, 16);
    }

    function stop() {
      if (observer) observer.disconnect();
      if (usingScrollFallback) window.removeEventListener('scroll', scheduleUpdate);
      if (nav) nav.removeEventListener('click', handleClick);
      setCurrent(null);
      observer = null;
      panel = null;
      nav = null;
      links = [];
      targets = [];
      usingScrollFallback = false;
    }

    function observe() {
      var viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
      var line = activationLine();
      var rootMargin = '-' + line + 'px 0px -' + Math.max(0, viewportHeight - line - 1) + 'px 0px';
      if (window.IntersectionObserver) {
        try {
          observer = new window.IntersectionObserver(scheduleUpdate, { rootMargin: rootMargin, threshold: 0 });
          targets.forEach(function (target) { observer.observe(target); });
          return;
        } catch (error) {
          observer = null;
        }
      }
      usingScrollFallback = true;
      window.addEventListener('scroll', scheduleUpdate);
    }

    function handleClick(event) {
      var link = event.target.closest('a[href^="#"]');
      var index = links.indexOf(link);
      var target = index < 0 ? null : targets[index];
      if (!link || !nav || !nav.contains(link) || !target) return;
      event.preventDefault();
      setCurrent(link);
      target.scrollIntoView({
        behavior: window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
        block: 'start'
      });
    }

    function bind() {
      var navs;
      stop();
      panel = activePanel();
      if (!panel) return;
      navs = toArray(panel.querySelectorAll('[data-section-nav]'));
      if (navs.length !== 1) return;
      nav = navs[0];
      links = toArray(nav.querySelectorAll('a[href^="#"]'));
      targets = links.map(targetFor);
      if (!targets.some(Boolean)) return;
      nav.addEventListener('click', handleClick);
      updateCurrent();
      observe();
    }

    scope.addEventListener('higgs:tabchange', bind);
    window.addEventListener('resize', bind);
    bind();
  }

  var controllers = toArray(document.querySelectorAll('[data-higgs-tabs]'))
    .map(initTabs)
    .filter(Boolean);

  controllers.forEach(initSectionNav);

  window.__higgsTabs = controllers;
}());
