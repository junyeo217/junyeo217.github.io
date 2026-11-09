(function () {
  'use strict';

  const tabs = Array.from(document.querySelectorAll('[data-work-tab]'));
  const panels = Array.from(document.querySelectorAll('[data-work-panel]'));
  if (!tabs.length) return;

  function activate(category) {
    tabs.forEach(function (tab) {
      const selected = tab.getAttribute('data-work-tab') === category;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
    });
    panels.forEach(function (panel) {
      panel.hidden = panel.getAttribute('data-work-panel') !== category;
      if (panel.hidden) {
        panel.querySelectorAll('video').forEach(function (video) { video.pause(); });
      }
    });
  }

  tabs.forEach(function (tab, index) {
    tab.addEventListener('click', function () { activate(tab.getAttribute('data-work-tab')); });
    tab.addEventListener('keydown', function (event) {
      let next;
      switch (event.key) {
        case 'ArrowRight': next = (index + 1) % tabs.length; break;
        case 'ArrowLeft': next = (index + tabs.length - 1) % tabs.length; break;
        case 'Home': next = 0; break;
        case 'End': next = tabs.length - 1; break;
        default: return;
      }
      event.preventDefault();
      const target = tabs[next];
      if (target) {
        activate(target.getAttribute('data-work-tab'));
        target.focus();
      }
    });
  });
  activate('film');
})();
