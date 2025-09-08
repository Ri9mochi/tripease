document.addEventListener("DOMContentLoaded", function() {
  const groupSelect = document.querySelector("[data-group-select]");
  const destinations = document.querySelectorAll("[data-prefecture-group]");

  if (!groupSelect) return;

  // 初期状態ですべて非表示
  destinations.forEach(el => el.style.display = "none");

  groupSelect.addEventListener("change", function() {
    const selectedGroupId = groupSelect.value;
    destinations.forEach(el => {
      if (selectedGroupId && el.dataset.prefectureGroup === selectedGroupId) {
        el.style.display = "block";
      } else {
        el.style.display = "none";
      }
    });
  });
});
