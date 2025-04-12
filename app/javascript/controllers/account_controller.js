import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    sortcodeField;

    connect() {
        this.sortcodeField = document.getElementById("sortcode");
        console.log("Hello, Stimulus!", this.element)
    }
    type_changed(event) {
        const accountType = event.target.value;

        if (accountType === "CreditCardAccount") {
            this.sortcodeField.style.display = "none";
            this.sortcodeField.disabled = true;
        } else {
            this.sortcodeField.style.display = "";
            this.sortcodeField.disabled = false;
        }
    }
}
