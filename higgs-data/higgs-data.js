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
      var value = decodeURIComponent(window.location.hash.slice(1));
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

    return {
      activate: activate,
      panels: tabs.map(panelFor).filter(Boolean),
      scope: scope,
      tabs: tabs
    };
  }

  var controllers = toArray(document.querySelectorAll('[data-higgs-tabs]'))
    .map(initTabs)
    .filter(Boolean);

  window.__higgsTabs = controllers;
}());
