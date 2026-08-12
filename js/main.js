/* 공통 스크립트 — 전 페이지 공유 */

/* 스크롤 리빌 + 지표 카운트업
   - [data-reveal]            개별 리빌 (data-delay로 수동 지연) — 기존과 동일
   - [data-reveal="wipe"]     위→아래 와이프 (CSS가 담당, 여기서는 is-in만 붙인다)
   - [data-reveal-group]      직계 자식을 순서대로 자동 스태거 (기본 90ms, 값으로 간격 지정 가능,
                              컨테이너의 data-delay는 전체 시작 지연)
   - [data-count="38"]        뷰포트 진입 시 0 → 값 카운트업 (선택: data-count-dur)
   reduced-motion / IntersectionObserver 부재 시에는 전부 즉시 최종 상태로 둔다. */
(function () {
  'use strict';

  var GROUP_STEP = 90;
  var COUNT_DUR = 900;

  var reduce = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

  function toArray(list) { return Array.prototype.slice.call(list); }

  var groups = toArray(document.querySelectorAll('[data-reveal-group]'));
  /* 그룹의 직계 자식은 그룹이 책임진다 — 개별 관찰에서 뺀다 */
  var solos = toArray(document.querySelectorAll('[data-reveal]')).filter(function (el) {
    var p = el.parentElement;
    return !(p && p.hasAttribute('data-reveal-group'));
  });
  /* 정수만 카운트업한다. 값이 없는 data-count(예: /log 필터 버튼의 건수 슬롯)는 건드리지 않는다 */
  function isCounter(el) { return /^\d+$/.test(el.getAttribute('data-count')); }
  /* 리빌 안에 든 숫자는 그 리빌과 같은 타이밍에 시작한다 — 이미 드러난 뒤에 세지 않게 */
  var counters = toArray(document.querySelectorAll('[data-count]')).filter(isCounter)
    .filter(function (el) {
      return !(el.closest && el.closest('[data-reveal], [data-reveal-group]'));
    });

  function showNow(el) { el.classList.add('is-in'); }

  if (reduce || !('IntersectionObserver' in window)) {
    solos.forEach(showNow);
    groups.forEach(function (g) { toArray(g.children).forEach(showNow); });
    return; /* 카운트업 없음 — 마크업의 최종값이 그대로 남는다 */
  }

  function reveal(el, delay) {
    if (delay) el.style.transitionDelay = delay + 'ms';
    el.classList.add('is-in');
    countInside(el, delay);
  }

  function countInside(el, delay) {
    var found = toArray(el.querySelectorAll('[data-count]'));
    if (el.hasAttribute('data-count')) found.unshift(el);
    found.filter(isCounter).forEach(function (c) {
      if (delay) window.setTimeout(function () { countUp(c); }, delay);
      else countUp(c);
    });
  }

  function countUp(el) {
    var target = parseInt(el.getAttribute('data-count'), 10);
    if (!(target >= 0)) return;
    var dur = parseInt(el.getAttribute('data-count-dur'), 10);
    if (!(dur > 0)) dur = COUNT_DUR;

    /* 자릿수가 늘며 뒤의 단위 라벨이 밀리지 않게 최종 폭을 미리 잡는다 (끝나면 되돌린다) */
    var display = el.style.display;
    var minWidth = el.style.minWidth;
    el.style.display = 'inline-block';
    el.style.minWidth = String(target).length + 'ch';

    var start = 0;
    el.textContent = '0';
    (function frame(now) {
      if (!start) start = now;
      var t = (now - start) / dur;
      if (t > 1) t = 1;
      var p = 1 - Math.pow(1 - t, 3); /* easeOut — 끝이 느리다 */
      el.textContent = String(Math.round(target * p));
      if (t < 1) { window.requestAnimationFrame(frame); return; }
      el.textContent = String(target);
      el.style.display = display;
      el.style.minWidth = minWidth;
    })(0);
  }

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (!e.isIntersecting) return;
      var el = e.target;
      io.unobserve(el);

      if (el.hasAttribute('data-reveal-group')) {
        var base = parseInt(el.getAttribute('data-delay'), 10) || 0;
        var step = parseInt(el.getAttribute('data-reveal-group'), 10) || GROUP_STEP;
        toArray(el.children).forEach(function (child, i) { reveal(child, base + i * step); });
      } else if (el.hasAttribute('data-reveal')) {
        reveal(el, parseInt(el.getAttribute('data-delay'), 10) || 0);
      } else if (isCounter(el)) {
        countUp(el);
      }
    });
  }, { threshold: 0.12 });

  groups.forEach(function (el) { io.observe(el); });
  solos.forEach(function (el) { io.observe(el); });
  counters.forEach(function (el) { io.observe(el); });

  /* 다른 스크립트에서 쓸 수 있게 최소한만 노출 (검증·수동 트리거용) */
  window.__reveal = { reveal: reveal, countUp: countUp };
})();

/* 현재 페이지 내비 표시 */
(function () {
  var page = document.body.getAttribute('data-page');
  if (!page) return;
  document.querySelectorAll('.nav-links a, .mobile-menu a').forEach(function (a) {
    if (a.getAttribute('data-nav') === page) a.setAttribute('aria-current', 'page');
  });
})();

/* 모바일 메뉴 */
(function () {
  var burger = document.querySelector('.nav-burger');
  var menu = document.querySelector('.mobile-menu');
  if (!burger || !menu) return;
  burger.addEventListener('click', function () {
    var open = menu.classList.toggle('open');
    burger.setAttribute('aria-expanded', open ? 'true' : 'false');
  });
  menu.addEventListener('click', function (e) {
    if (e.target.tagName === 'A') menu.classList.remove('open');
  });
})();
