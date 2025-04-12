import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [ "date" ];

    dateTargetConnected() {
        const rawDate = this.element.dataset.date;

        // Format the date in the browser's locale
        const formattedDate = new Intl.DateTimeFormat(navigator.language, {
            year: "numeric",
            month: "long",
            day: "numeric",
        }).format(new Date(rawDate));

        // Update the element with the formatted date
        this.dateTarget.innerHTML = formattedDate;
    }
}
