import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["groupSelect", "destination"]

  connect() {
    // ページ読み込み時に、全てのチェックボックスを非表示にする
    this.destinationTargets.forEach(el => {
      el.style.display = "none";
    });
  }

  update() {
    const selectedGroupId = this.groupSelectTarget.value

    this.destinationTargets.forEach(el => {
      // 選択されたグループIDが空の場合は全て非表示
      if (selectedGroupId && el.dataset.prefectureGroup === selectedGroupId) {
        el.style.display = "block"
      } else {
        el.style.display = "none"
      }
    })
  }
}