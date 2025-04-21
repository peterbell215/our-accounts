import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "categoryForm" ]

  connect() {
    // console.log("Transaction row controller connected", this.element);
  }

  saveCategory(event) {
    // console.log("Save button clicked, submitting form:", this.categoryFormTarget);
    // Programmatically submit the form targeted within this controller instance.
    // requestSubmit() triggers the form's submit event, allowing Turbo Drive
    // to intercept it just like a regular submit button click.
    this.categoryFormTarget.requestSubmit();
  }
}
