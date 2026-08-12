/* 공통 스크립트 — 전 페이지 공유 */

/* 스크롤 리빌 + 지표 카운트업
   - [data-reveal]            개별 리빌 (data-delay로 수동 지연) — 기존과 동일
   - [data-reveal="wipe"]     위→아래 와이프 (CSS가 담당, 여기서는 is-in만 붙인다)
   - [data-reveal-group]      직계 자식을 순서대로 자동 스태거 (기본 90ms, 값으로 간격 지정 가능,
                              컨테이너의 data-delay는 전체 시작 지연)
   - [data-count="38"]        뷰포트 진입 시 0 → 값 카운트업 (선택: data-count-dur)
                              최종값은 HTML이 갖고 있고 JS는 애니메이션만 한다 — 프레임이 오지
                              않는 환경에서는 마크업의 최종값이 그대로 남는다.
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

  /* 카운트업은 "장식"이다 — 최종값은 언제나 HTML에 있고 JS는 애니메이션만 맡는다.
     그래서 시작 시 0으로 덮지 않고, 첫 rAF 프레임이 실제로 도착한 뒤부터 숫자를 갱신한다.
     프레임이 영영 오지 않는 환경(백그라운드 탭·헤드리스 렌더)에서는 마크업의 최종값이 그대로 남는다. */
  function countUp(el) {
    var target = parseInt(el.getAttribute('data-count'), 10);
    if (!(target >= 0)) return;
    if (el.__counting) return;                 /* 이중 호출 방지 — 원복용 인라인 스타일을 덮어쓰지 않게 */
    if (!window.requestAnimationFrame) return; /* rAF 없음 → 최종값 유지 */
    if (document.hidden) return;               /* 탭이 숨어 있으면 프레임이 안 온다 → 최종값 유지 */

    var dur = parseInt(el.getAttribute('data-count-dur'), 10);
    if (!(dur > 0)) dur = COUNT_DUR;

    el.__counting = true;

    /* 자릿수가 늘며 뒤의 단위 라벨이 밀리지 않게 최종 폭을 미리 잡는다 (끝나면 되돌린다) */
    var display = el.style.display;
    var minWidth = el.style.minWidth;
    el.style.display = 'inline-block';
    el.style.minWidth = String(target).length + 'ch';

    var done = false;
    var timer = 0;

    function settle() {
      if (done) return;                        /* 두 번 불려도 안전하다 */
      done = true;
      if (timer) window.clearTimeout(timer);
      el.textContent = String(target);
      el.style.display = display;
      el.style.minWidth = minWidth;
      el.__counting = false;
    }

    /* 안전장치 — 프레임이 끊기거나 도중에 탭이 숨어도 최종값·스타일은 반드시 돌아온다 */
    timer = window.setTimeout(settle, dur + 600);

    var start = -1;
    window.requestAnimationFrame(function frame(now) {
      if (done) return;
      if (start < 0) start = now;               /* 첫 프레임 전까지 텍스트는 마크업 최종값 그대로 */
      var t = (now - start) / dur;
      if (t < 0) t = 0; else if (t > 1) t = 1;
      if (t >= 1) { settle(); return; }
      var p = 1 - Math.pow(1 - t, 3);           /* easeOut — 끝이 느리다 */
      el.textContent = String(Math.round(target * p));
      window.requestAnimationFrame(frame);
    });
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

/* ============================================================
   커스텀 커서 — 8px 도트가 마우스를 따라오고, 대상에 따라 원으로 벌어진다.
   · 마크업은 여기서 주입한다 (각 html 수정 불필요)
   · 게이트: (pointer: fine) + reduced-motion 아님 + rAF 있음
     → 통과했을 때만 <html class="has-cursor">가 붙고 그때만 CSS가 네이티브 커서를 숨긴다.
       JS가 죽으면 클래스가 안 붙으므로 네이티브 커서가 그대로 남는다.
   · 좌표는 pointermove에서 기록만 하고 실제 이동은 rAF에서 (프레임당 1회)
   · hover 판정은 pointerover 위임 — 노드마다 리스너를 달지 않는다
   ============================================================ */
(function () {
  'use strict';

  var root = document.documentElement;
  if (!document.body || !window.matchMedia || !window.requestAnimationFrame) return;
  if (!window.matchMedia('(pointer: fine)').matches) return;                 /* 터치 기기 제외 */
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return; /* 모션 축소면 비활성 */

  var HOVER_SEL = 'a, button, [role="tab"], .card';
  var VIEW_SEL = 'video:not(.hero-video)';   /* 히어로 루프는 컨트롤이 없어 제외 */
  var NATIVE_SEL = 'input, textarea, select, iframe, [contenteditable="true"]';
  var LERP = 0.22;

  var el = document.createElement('div');
  el.className = 'cursor';
  el.setAttribute('aria-hidden', 'true');
  var ring = document.createElement('div');
  ring.className = 'cursor-ring';
  var label = document.createElement('span');
  label.className = 'cursor-label';
  label.textContent = 'View';
  ring.appendChild(label);
  el.appendChild(ring);

  var tx = 0, ty = 0, x = 0, y = 0, raf = 0, seen = false;

  function paint() {
    el.style.transform = 'translate3d(' + x.toFixed(1) + 'px,' + y.toFixed(1) + 'px,0)';
  }

  function draw() {
    raf = 0;
    var dx = tx - x, dy = ty - y;
    if (Math.abs(dx) < 0.1 && Math.abs(dy) < 0.1) { x = tx; y = ty; paint(); return; }
    x += dx * LERP;
    y += dy * LERP;
    paint();
    raf = window.requestAnimationFrame(draw);
  }

  function onMove(e) {
    tx = e.clientX;
    ty = e.clientY;
    if (!seen) { seen = true; x = tx; y = ty; paint(); }   /* 첫 좌표는 스무딩 없이 스냅 */
    el.classList.add('is-on');
    if (!raf) raf = window.requestAnimationFrame(draw);
  }

  /* 대상에 따른 상태 — view(비디오) > hover(인터랙티브) 순으로 본다 */
  function setState(node) {
    var t = (node && node.closest) ? node : null;
    var view = !!(t && t.closest(VIEW_SEL));
    var cl = el.classList;
    cl.toggle('is-view', view);
    cl.toggle('is-hover', !view && !!(t && t.closest(HOVER_SEL)));
    cl.toggle('is-native', !!(t && t.closest(NATIVE_SEL)));  /* 입력 위에서는 네이티브로 */
  }

  function onOver(e) { setState(e.target); }
  function onOut(e) { if (!e.relatedTarget) el.classList.remove('is-on'); } /* 창 밖으로 나감 */
  function onBlur() { el.classList.remove('is-on'); }

  function enable() {
    document.body.appendChild(el);
    root.classList.add('has-cursor');
    document.addEventListener('pointermove', onMove, { passive: true });
    document.addEventListener('pointerover', onOver, true);
    document.addEventListener('pointerout', onOut, true);
    window.addEventListener('blur', onBlur);
  }

  /* 인트로 오버레이(z-index 1000)는 커서(900)보다 위다 — 걷힌 뒤에 켠다.
     home.js가 죽어도 인덱스의 하드캡(3.6s)이 intro-on을 떼므로 타이머로 보증한다. */
  if (root.classList.contains('intro-on')) {
    var started = false;
    var mo = null;
    var start = function () {
      if (started) return;
      started = true;
      if (mo) mo.disconnect();
      enable();
    };
    if (window.MutationObserver) {
      mo = new MutationObserver(function () {
        if (!root.classList.contains('intro-on')) start();
      });
      mo.observe(root, { attributes: true, attributeFilter: ['class'] });
    }
    window.setTimeout(start, 3800);
  } else {
    enable();
  }

  /* 검증·수동 트리거용 */
  window.__cursor = { el: el, setState: setState };
})();
