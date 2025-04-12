import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["sortcode"];

    type_changed(event) {
        const accountType = event.target.value;

        if (accountType === "CreditCardAccount") {
            this.sortcodeTarget.style.display = "none";
            this.sortcodeTarget.disabled = true;
        } else {
            this.sortcodeTarget.style.display = "";
            this.sortcodeTarget.disabled = false;
        }
    }
}
