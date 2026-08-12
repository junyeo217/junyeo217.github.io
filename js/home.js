/* ============================================================
   home.js — 홈 `/` 전용
   (0) 타이핑 인트로: IME 조합 과정을 그대로 재현하고 3초 안에 끝낸다.
   외부 라이브러리 없음.
   ============================================================ */

(function () {
  'use strict';

  var root = document.documentElement;
  var overlay = document.getElementById('intro');
  var line = document.getElementById('introLine');
  var textEl = document.getElementById('introText');

  function markDone() {
    root.classList.remove('intro-on');
    root.classList.add('intro-done');
  }

  /* reduced-motion 이거나 마크업이 없으면 인트로 자체를 생략 */
  if (!overlay || !line || !textEl || !root.classList.contains('intro-on')) {
    markDone();
    if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay);
    return;
  }

  /* ---- 타이밍 설계 (합계 ≈ 2.82s, HARD_CAP 3.0s로 상한 고정) ---- */
  var T = {
    START: 80,          // 오버레이 표시 후 첫 타건까지
    KEY1_MIN: 40,       // 1행 타건 간격 (랜덤)
    KEY1_MAX: 80,
    HOLD_AFTER_L1: 160, // "끝내자" 완성 후 멈춤
    STRIKE: 200,        // 취소선이 그어지는 시간 (CSS transition과 동일)
    AFTER_STRIKE: 100,  // 그어진 채로 멈춤
    DEL: 45,            // 백스페이스 1회
    GAP: 80,            // 지워지고 나서 2행 시작까지
    KEY2_MIN: 26,       // 2행 타건 간격 — 문장이 길어 1행보다 압축
    KEY2_MAX: 46,
    HOLD_END: 180,      // "…해" 완성 후 홀드
    FADE: 260,          // 오버레이 페이드아웃 (CSS와 동일)
    HARD_CAP: 3000      // 무슨 일이 있어도 이 시각에 종료
  };

  /* ---- IME 조합 시퀀스 ----
     각 배열은 한 음절을 완성하기까지의 조합 상태. ' ' 하나면 공백 확정. */
  var LINE1 = [
    ['ㄲ', '끄', '끝'],   // ㄲ → 끄 → 끝
    ['ㄴ', '내'],         // 끝ㄴ → 끝내
    ['ㅈ', '자']          // 끝내ㅈ → 끝내자
  ];

  var LINE2 = [
    ['ㄴ', '너'], ['ㄱ', '가'], [' '],
    ['ㅎ', '히', '힘'], ['ㄷ', '드', '들'], ['ㅈ', '지'], [' '],
    ['ㅇ', '아', '안', '않'], ['ㅇ', '아', '았'], ['ㅇ', '으'], ['ㅁ', '며', '면'], [' '],
    ['ㅎ', '해']
  ];

  /* 조합 시퀀스 → 프레임 목록 [committed, composing] */
  function buildFrames(groups) {
    var frames = [];
    var committed = '';
    for (var g = 0; g < groups.length; g++) {
      var steps = groups[g];
      if (steps.length === 1 && steps[0] === ' ') {
        committed += ' ';
        frames.push([committed, '']);
        continue;
      }
      for (var s = 0; s < steps.length; s++) frames.push([committed, steps[s]]);
      committed += steps[steps.length - 1];
    }
    frames.push([committed, '']); // 최종 확정
    return frames;
  }

  var F1 = buildFrames(LINE1);
  var F2 = buildFrames(LINE2);

  function rand(min, max) { return min + Math.random() * (max - min); }

  function esc(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function paint(committed, composing) {
    textEl.innerHTML = esc(committed) +
      (composing ? '<span class="intro-composing">' + esc(composing) + '</span>' : '');
  }

  /* ---- 실행 ---- */
  var alive = true;
  var timers = [];

  function later(fn, ms) {
    var id = window.setTimeout(function () { if (alive) fn(); }, ms);
    timers.push(id);
    return id;
  }

  function finish() {
    if (!alive) return;
    alive = false;
    for (var i = 0; i < timers.length; i++) window.clearTimeout(timers[i]);
    timers.length = 0;
    document.removeEventListener('keydown', skip, true);
    overlay.removeEventListener('pointerdown', skip);
    overlay.classList.add('is-out');
    markDone();
    window.setTimeout(function () {
      if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
    }, T.FADE);
  }

  function skip() { finish(); }

  document.addEventListener('keydown', skip, true);
  overlay.addEventListener('pointerdown', skip);

  /* 3초 하드 캡 — 중간에 무엇이 어긋나도 반드시 끝난다 */
  window.setTimeout(function () { if (alive) finish(); }, T.HARD_CAP);

  function typeFrames(frames, min, max, done) {
    var i = 0;
    (function step() {
      if (!alive) return;
      if (i >= frames.length) { done(); return; }
      paint(frames[i][0], frames[i][1]);
      i++;
      later(step, rand(min, max));
    })();
  }

  function deleteAll(text, done) {
    var n = text.length;
    (function step() {
      if (!alive) return;
      if (n <= 0) { paint('', ''); done(); return; }
      n--;
      paint(text.slice(0, n), '');
      later(step, T.DEL);
    })();
  }

  try {
    later(function () {
      // 1) "끝내자" 타이핑
      typeFrames(F1, T.KEY1_MIN, T.KEY1_MAX, function () {
        // 2) 잠깐 멈춤 → 취소선 → 지우기
        later(function () {
          line.classList.add('is-struck');
          later(function () {
            line.classList.remove('is-struck');
            deleteAll('끝내자', function () {
              // 3) "너가 힘들지 않았으면 해" 타이핑
              later(function () {
                typeFrames(F2, T.KEY2_MIN, T.KEY2_MAX, function () {
                  // 4) 짧은 홀드 후 페이드아웃
                  later(finish, T.HOLD_END);
                });
              }, T.GAP);
            });
          }, T.STRIKE + T.AFTER_STRIKE);
        }, T.HOLD_AFTER_L1);
      });
    }, T.START);
  } catch (e) {
    finish();
  }
})();

/* ============================================================
   내비 투명 ↔ 종이 전환 — 홈 전용
   히어로 하단 sentinel을 IntersectionObserver로 감시한다.
   rootMargin 상단 -64px = 내비 높이 → sentinel이 내비 아래에 있는 동안
   (= 내비 띠가 히어로 위에 얹혀 있는 동안) .is-over-hero를 붙인다.
   실패 시(구형 브라우저·마크업 부재) 클래스가 붙지 않아 종이 스타일로 남는다.
   ============================================================ */
(function () {
  var nav = document.querySelector('.nav');
  var sentinel = document.getElementById('heroSentinel');
  if (!nav || !sentinel || !('IntersectionObserver' in window)) return;

  var io = new IntersectionObserver(function (entries) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].isIntersecting) nav.classList.add('is-over-hero');
      else nav.classList.remove('is-over-hero');
    }
  }, { rootMargin: '-64px 0px 0px 0px', threshold: 0 });

  io.observe(sentinel);
})();

/* iOS Safari 자동재생 보장 — 속성만으로는 부족해 프로퍼티로도 세팅 */
(function () {
  var v = document.querySelector('.hero-video');
  if (!v) return;
  v.muted = true;
  v.playsInline = true;
  /* 본편 도입부(검은 타이핑 카드)를 건너뛰고 시작 — 루프 복귀 시에는 자연 진행 */
  var seekIntro = function () {
    if (v.currentTime < 1) { try { v.currentTime = 8; } catch (e) {} }
  };
  if (v.readyState >= 1) seekIntro();
  else v.addEventListener('loadedmetadata', seekIntro, { once: true });
  var p = v.play();
  if (p && p.catch) p.catch(function () {});
})();
