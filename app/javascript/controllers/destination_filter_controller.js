import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["groupSelect", "destination"]

  connect() {
    // ページ読み込み時に、全ての都道府県チェックボックスを非表示にする
    this.destinationTargets.forEach(el => {
      el.style.display = "none";
    });
  }

  update() {
    const selectedGroupId = this.groupSelectTarget.value

    this.destinationTargets.forEach(el => {
      // 選択されたグループIDと一致する都道府県だけ表示
      if (selectedGroupId && el.dataset.prefectureGroup === selectedGroupId) {
        el.style.display = "block"
      } else {
        el.style.display = "none"
      }
    })
  }
}