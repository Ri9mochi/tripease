function initDestinationFilter() {
  const groupSelect = document.querySelector("[data-group-select]");
  const destinations = document.querySelectorAll(".destination-item"); // ← クラスを使う
  if (!groupSelect || destinations.length === 0) return;

  const apply = () => {
    const selectedGroupId = groupSelect.value;
    destinations.forEach(el => {
      el.style.display =
        selectedGroupId && el.dataset.prefectureGroup === selectedGroupId
          ? "block"
          : "none";
    });
  };

  // いったん全て隠す（CSSで隠してるが念のため）
  destinations.forEach(el => (el.style.display = "none"));

  // 変更イベント
  groupSelect.removeEventListener("change", apply);
  groupSelect.addEventListener("change", apply);

  // ★ 初回実行（ここが重要）
  apply();
}

// いろんな経路で来ても実行されるように
document.addEventListener("turbo:load", initDestinationFilter);
document.addEventListener("turbo:render", initDestinationFilter);
document.addEventListener("turbo:frame-load", initDestinationFilter);
document.addEventListener("DOMContentLoaded", initDestinationFilter);

// ★ フルリロード直後など、イベントを取り逃しても動くよう“即時”も呼ぶ
initDestinationFilter();
