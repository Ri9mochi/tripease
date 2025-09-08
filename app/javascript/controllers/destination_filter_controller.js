import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["groupSelect", "destination"]

  connect() {

    this.destinationTargets.forEach(el => {
      el.style.display = "none";
    });
  }

  update() {
    const selectedGroupId = this.groupSelectTarget.value

    this.destinationTargets.forEach(el => {

      if (selectedGroupId && el.dataset.prefectureGroup === selectedGroupId) {
        el.style.display = "block"
      } else {
        el.style.display = "none"
      }
    })
  }
}