import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["groupSelect", "destination"]

  connect() {
    this.update() // ページ読み込み時も非表示にする
  }

  update() {
    const selectedGroupId = this.groupSelectTarget.value

    this.destinationTargets.forEach(el => {
      // 選択が空の場合は全て非表示
      if (selectedGroupId && el.dataset.prefectureGroup === selectedGroupId) {
        el.style.display = "block"
      } else {
        el.style.display = "none"
      }
    })
  }
}
