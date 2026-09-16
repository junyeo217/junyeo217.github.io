(function () {
  'use strict';
  var root = document.documentElement;
  var buttons = Array.from(document.querySelectorAll('[data-language]'));
  var textNodes = Array.from(document.querySelectorAll('[data-en]')).map(function (el) {
    return { el: el, ko: el.innerHTML, en: el.getAttribute('data-en') };
  });
  var attributes = [];
  ['aria-label', 'label', 'intro'].forEach(function (name) {
    document.querySelectorAll('[data-en-' + name + ']').forEach(function (el) {
      var attribute = name === 'intro' ? 'data-intro-text' : name;
      attributes.push({ el: el, name: attribute, ko: el.getAttribute(attribute), en: el.getAttribute('data-en-' + name) });
    });
  });
  var description = document.querySelector('meta[name="description"]');
  var originalDescription = description.content;
  function applyLanguage(lang, save) {
    lang = lang === 'en' ? 'en' : 'ko';
    root.lang = lang;
    textNodes.forEach(function (item) { item.el.innerHTML = item[lang]; });
    attributes.forEach(function (item) { item.el.setAttribute(item.name, item[lang]); });
    buttons.forEach(function (button) { button.setAttribute('aria-pressed', button.dataset.language === lang ? 'true' : 'false'); });
    var name = lang === 'en' ? 'Joonghyun Cho' : '조중현';
    document.title = name + ' | AI Filmmaker Portfolio';
    description.content = lang === 'en' ? 'The film portfolio of Joonghyun Cho, a video creator and software builder crafting stories with generative AI. Featuring Missed Call and I Hope You Won’t Have to Struggle.' : originalDescription;
    document.querySelector('meta[name="author"]').content = name;
    document.querySelector('meta[property="og:title"]').content = document.title;
    document.querySelector('meta[property="og:locale"]').content = lang === 'en' ? 'en_US' : 'ko_KR';
    document.querySelector('meta[property="og:site_name"]').content = name + (lang === 'en' ? ' Portfolio' : ' 포트폴리오');
    document.querySelector('meta[property="og:description"]').content = lang === 'en' ? 'I create scenes with AI and bring them together through story.' : 'AI로 장면을 만들고, 이야기로 완성합니다.';
    if (save) {
      try { localStorage.setItem('portfolio-language', lang); } catch (e) {}
      var url = new URL(location.href);
      if (lang === 'en') url.searchParams.set('lang', 'en');
      else url.searchParams.delete('lang');
      history.replaceState(history.state, '', url.pathname + url.search + url.hash);
    }
  }
  var initial = new URLSearchParams(location.search).get('lang');
  if (initial !== 'ko' && initial !== 'en') {
    try { initial = localStorage.getItem('portfolio-language'); } catch (e) {}
  }
  applyLanguage(initial, false);
  buttons.forEach(function (button) {
    button.addEventListener('click', function () { applyLanguage(button.dataset.language, true); });
  });
  window.addEventListener('popstate', function () {
    var lang = new URLSearchParams(location.search).get('lang');
    applyLanguage(lang || root.lang, false);
  });
})();
