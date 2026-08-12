/* /film 전용 — 페이지 안에 영상이 여럿이라(본편 + S04C 전/후) 하나가 재생되면
   나머지는 일시정지한다. 두 소리가 겹치면 전/후 대조 자체가 성립하지 않는다. */
(function () {
  var videos = Array.prototype.slice.call(document.querySelectorAll('video'));
  if (videos.length < 2) return;

  videos.forEach(function (v) {
    v.addEventListener('play', function () {
      videos.forEach(function (other) {
        if (other !== v && !other.paused) other.pause();
      });
    });
  });
})();
