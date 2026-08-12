/* /experiment 전용 — 전체 대조표 필터 (전체 / 개정 / 유지 / 복원)
   JS가 없으면 필터 바는 hidden 상태로 남고 38행이 전부 보인다. */
(function () {
  var bar = document.querySelector('[data-xp-filter]');
  if (!bar) return;

  var blocks = Array.prototype.slice.call(document.querySelectorAll('[data-xp-scene]'));
  if (!blocks.length) return;

  var btns = Array.prototype.slice.call(bar.querySelectorAll('button[data-filter]'));
  if (!btns.length) return;

  var count = bar.querySelector('[data-xp-count]');
  var total = document.querySelectorAll('[data-xp-scene] tbody tr').length;

  function match(tr, key) {
    if (key === 'all') return true;
    if (key === 'restored') return tr.getAttribute('data-restored') === 'true';
    return tr.getAttribute('data-kind') === key;
  }

  function apply(key) {
    var shown = 0;

    blocks.forEach(function (block) {
      var rows = Array.prototype.slice.call(block.querySelectorAll('tbody tr'));
      var visible = 0;

      rows.forEach(function (tr) {
        if (match(tr, key)) {
          tr.removeAttribute('hidden');
          visible++;
        } else {
          tr.setAttribute('hidden', '');
        }
      });

      shown += visible;
      if (visible) block.removeAttribute('hidden');
      else block.setAttribute('hidden', '');
    });

    btns.forEach(function (b) {
      b.setAttribute('aria-pressed', b.getAttribute('data-filter') === key ? 'true' : 'false');
    });

    if (count) count.textContent = total + '행 중 ' + shown + '행 표시';
  }

  bar.addEventListener('click', function (e) {
    var b = e.target.closest ? e.target.closest('button[data-filter]') : null;
    if (b && btns.indexOf(b) !== -1) apply(b.getAttribute('data-filter'));
  });

  bar.hidden = false;
  apply('all');
})();
