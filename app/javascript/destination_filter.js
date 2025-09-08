function initDestinationFilter() {
  const groupSelect = document.querySelector("[data-group-select]");
  const destinations = document.querySelectorAll("[data-prefecture-group]");
  console.log("[destFilter] init, groupSelect:", !!groupSelect, "destinations:", destinations.length);

  if (!groupSelect || destinations.length === 0) return;

  // 初期状態は全て非表示（未選択のとき全表示にしたい場合は下のVariant参照）
  destinations.forEach(el => el.style.display = "none");

  const apply = () => {
    const selectedGroupId = groupSelect.value;
    let shown = 0;
    destinations.forEach(el => {
      const match = selectedGroupId && el.dataset.prefectureGroup === selectedGroupId;
      el.style.display = match ? "block" : "none";
      if (match) shown++;
    });
    console.log("[destFilter] change -> value:", selectedGroupId, "shown:", shown);
  };

  // 二重登録ガード
  groupSelect.removeEventListener("change", apply);
  groupSelect.addEventListener("change", apply);

  // 初回適用（選び直していないと何も見えないため）
  apply();
}

document.addEventListener("turbo:load", initDestinationFilter);
document.addEventListener("DOMContentLoaded", initDestinationFilter);
