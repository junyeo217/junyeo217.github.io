/* /film 전용 — 파생판 탭 전환 (WAI-ARIA Tabs 패턴) */
(function () {
  var tablist = document.querySelector('[data-tabs]');
  if (!tablist) return;

  var tabs = Array.prototype.slice.call(tablist.querySelectorAll('[role="tab"]'));
  if (!tabs.length) return;

  function panelOf(tab) {
    return document.getElementById(tab.getAttribute('aria-controls'));
  }

  function select(tab, moveFocus) {
    tabs.forEach(function (t) {
      var on = (t === tab);
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      t.setAttribute('tabindex', on ? '0' : '-1');
      var panel = panelOf(t);
      if (!panel) return;
      if (on) panel.removeAttribute('hidden');
      else panel.setAttribute('hidden', '');
    });
    if (moveFocus) tab.focus();
  }

  tablist.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target.closest('[role="tab"]') : null;
    if (t && tabs.indexOf(t) !== -1) select(t, false);
  });

  tablist.addEventListener('keydown', function (e) {
    var i = tabs.indexOf(document.activeElement);
    if (i === -1) return;
    var next = null;
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') next = tabs[(i + 1) % tabs.length];
    else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') next = tabs[(i - 1 + tabs.length) % tabs.length];
    else if (e.key === 'Home') next = tabs[0];
    else if (e.key === 'End') next = tabs[tabs.length - 1];
    if (!next) return;
    e.preventDefault();
    select(next, true);
  });
})();
