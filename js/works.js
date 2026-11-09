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

  document.querySelectorAll('[data-series-open]').forEach(function (link) {
    const dialog = document.getElementById(link.dataset.seriesOpen);
    if (!dialog || typeof dialog.showModal !== 'function') return;
    const video = dialog.querySelector('video');
    const episodes = Array.from(dialog.querySelectorAll('[data-episode]'));
    const status = dialog.querySelector('.episode-status');
    let selected = episodes[0];

    function updateLabel() {
      const title = selected.querySelector('[data-en]').textContent;
      video.setAttribute('aria-label', title);
      status.textContent = title;
    }

    function selectEpisode(episode) {
      selected = episode;
      video.pause();
      video.src = episode.href;
      video.poster = episode.dataset.poster;
      video.classList.toggle('is-portrait', episode.dataset.portrait === 'true');
      episodes.forEach(function (item) {
        if (item === episode) item.setAttribute('aria-current', 'true');
        else item.removeAttribute('aria-current');
      });
      updateLabel();
      video.load();
    }

    link.addEventListener('click', function (event) {
      event.preventDefault();
      document.querySelectorAll('video').forEach(function (item) { item.pause(); });
      selectEpisode(selected);
      dialog.showModal();
      dialog.scrollTop = 0;
    });
    episodes.forEach(function (episode) {
      episode.addEventListener('click', function (event) {
        event.preventDefault();
        selectEpisode(episode);
        video.focus();
        video.scrollIntoView({ block: 'nearest' });
      });
    });
    function releasePlayer() {
      if (dialog.open) return;
      video.pause();
      video.removeAttribute('src');
      video.load();
      link.focus({ preventScroll: true });
    }
    function closeSeries() {
      dialog.close();
      releasePlayer();
    }
    dialog.querySelector('[data-series-close]').addEventListener('click', closeSeries);
    dialog.addEventListener('cancel', function (event) {
      event.preventDefault();
      closeSeries();
    });
    dialog.addEventListener('close', releasePlayer);
    document.addEventListener('portfolio-language-change', updateLabel);
  });
})();
