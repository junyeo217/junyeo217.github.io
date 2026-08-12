/* /log 전용 — 시기 필터 (토글 버튼 그룹, aria-pressed)
   film.js의 탭 패턴과 같은 계열이지만 여기는 tablist가 아니라 필터 그룹이므로
   role="group" + aria-pressed 단일 선택으로 구현한다.
   필터는 여러 그룹(핀 카드 / 릴리즈 노트)에 동시에 걸린다. */
(function () {
  var group = document.querySelector('[data-log-filter]');
  if (!group) return;

  var btns = Array.prototype.slice.call(group.querySelectorAll('[data-filter]'));
  var groups = Array.prototype.slice.call(document.querySelectorAll('[data-log-group]'))
    .map(function (el) {
      return {
        el: el,
        name: el.getAttribute('data-group-name') || '',
        unit: el.getAttribute('data-group-unit') || '건',
        items: Array.prototype.slice.call(el.querySelectorAll('[data-phase]')),
        empty: el.querySelector('[data-group-empty]')
      };
    })
    .filter(function (g) { return g.items.length; });

  var status = document.querySelector('[data-filter-status]');
  if (!btns.length || !groups.length) return;

  function matches(item, key) {
    if (key === 'all') return true;
    var phases = (item.getAttribute('data-phase') || '').split(/\s+/);
    return phases.indexOf(key) !== -1;
  }

  /* 버튼의 건수 라벨은 DOM에서 다시 센다 — 항목이 늘어도 마크업 수정 없이 맞는다 */
  btns.forEach(function (b) {
    var slot = b.querySelector('[data-count]');
    if (!slot) return;
    var key = b.getAttribute('data-filter');
    var n = 0;
    groups.forEach(function (g) {
      g.items.forEach(function (it) { if (matches(it, key)) n++; });
    });
    slot.textContent = n;
  });

  function apply(key, btn) {
    var parts = [];

    groups.forEach(function (g) {
      var shown = 0;
      g.items.forEach(function (it) {
        if (matches(it, key)) {
          it.hidden = false;
          /* 필터로 다시 나타난 항목이 리빌 대기 상태(opacity 0)로 남지 않게 한다 */
          if (it.hasAttribute('data-reveal')) it.classList.add('is-in');
          var inner = it.querySelectorAll('[data-reveal]');
          Array.prototype.forEach.call(inner, function (el) { el.classList.add('is-in'); });
          shown++;
        } else {
          it.hidden = true;
        }
      });
      if (g.empty) g.empty.hidden = shown > 0;
      parts.push(g.name + ' ' + shown + g.unit);
    });

    btns.forEach(function (b) {
      b.setAttribute('aria-pressed', b === btn ? 'true' : 'false');
    });

    if (status) {
      status.textContent = btn.getAttribute('data-name') + ' — ' + parts.join(' · ') + ' 표시 중';
    }
  }

  group.addEventListener('click', function (e) {
    var b = e.target.closest ? e.target.closest('[data-filter]') : null;
    if (!b || btns.indexOf(b) === -1) return;
    apply(b.getAttribute('data-filter'), b);
  });
})();
