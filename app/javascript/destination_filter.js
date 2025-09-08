function initDestinationFilter() {
  const groupSelect = document.querySelector("[data-group-select]");
  const destinations = document.querySelectorAll("[data-prefecture-group]");
  if (!groupSelect || destinations.length === 0) return;

  // 初期状態：全て非表示（「未選択」のときは全表示にしたいなら後述のVariantを使用）
  destinations.forEach(el => el.style.display = "none");

  const apply = () => {
    const selectedGroupId = groupSelect.value;
    destinations.forEach(el => {
      el.style.display =
        selectedGroupId && el.dataset.prefectureGroup === selectedGroupId
          ? "block"
          : "none";
    });
  };

  groupSelect.removeEventListener("change", apply);
  groupSelect.addEventListener("change", apply);
}

document.addEventListener("turbo:load", initDestinationFilter);
document.addEventListener("DOMContentLoaded", initDestinationFilter);
