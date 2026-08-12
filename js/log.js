/* /log 전용 — 시기 필터 (토글 버튼 그룹, aria-pressed)
   film.js의 탭 패턴과 같은 계열이지만 여기는 tablist가 아니라 필터 그룹이므로
   role="group" + aria-pressed 단일 선택으로 구현한다. */
(function () {
  var group = document.querySelector('[data-log-filter]');
  var grid = document.querySelector('[data-log-grid]');
  if (!group || !grid) return;

  var btns = Array.prototype.slice.call(group.querySelectorAll('[data-filter]'));
  var cards = Array.prototype.slice.call(grid.querySelectorAll('[data-phase]'));
  var status = document.querySelector('[data-filter-status]');
  if (!btns.length || !cards.length) return;

  function phasesOf(card) {
    return (card.getAttribute('data-phase') || '').split(/\s+/).filter(Boolean);
  }

  function matches(card, key) {
    return key === 'all' || phasesOf(card).indexOf(key) !== -1;
  }

  /* 버튼의 건수 라벨은 DOM에서 다시 센다 — 카드가 늘어도 마크업 수정 없이 맞는다 */
  btns.forEach(function (b) {
    var slot = b.querySelector('[data-count]');
    if (!slot) return;
    var key = b.getAttribute('data-filter');
    slot.textContent = cards.filter(function (c) { return matches(c, key); }).length;
  });

  function apply(key, btn) {
    var shown = 0;
    cards.forEach(function (c) {
      if (matches(c, key)) {
        c.hidden = false;
        /* 필터로 다시 나타난 카드가 리빌 대기 상태(opacity 0)로 남지 않게 한다 */
        c.classList.add('is-in');
        shown++;
      } else {
        c.hidden = true;
      }
    });

    btns.forEach(function (b) {
      b.setAttribute('aria-pressed', b === btn ? 'true' : 'false');
    });

    if (status) {
      status.textContent = (key === 'all')
        ? '핀 ' + shown + '건 전부 표시 중'
        : btn.getAttribute('data-name') + ' — ' + cards.length + '건 중 ' + shown + '건 표시 중';
    }
  }

  group.addEventListener('click', function (e) {
    var b = e.target.closest ? e.target.closest('[data-filter]') : null;
    if (!b || btns.indexOf(b) === -1) return;
    apply(b.getAttribute('data-filter'), b);
  });
})();
