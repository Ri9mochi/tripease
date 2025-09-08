document.addEventListener("DOMContentLoaded", function() {
  const groupSelect = document.querySelector("[data-group-select]");
  const destinations = document.querySelectorAll("[data-prefecture-group]");

  if (!groupSelect) return;

  destinations.forEach(el => el.style.display = "none");

  groupSelect.addEventListener("change", function() {
    const selectedGroupId = groupSelect.value;
    destinations.forEach(el => {
      el.style.display = (selectedGroupId && el.dataset.prefectureGroup === selectedGroupId) ? "block" : "none";
    });
  });
});
