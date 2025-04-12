import { Controller } from "@hotwired/stimulus"

const dateTimeFormatter = new Intl.DateTimeFormat(navigator.language, {
    year: "numeric",
    month: "long",
    day: "numeric",
});

// This controller formats a date string in the browser's locale
export default class extends Controller {
    static targets = [ "date" ];

    dateTargetConnected() {
        const rawDate = this.element.dataset.date;

        // Format the date in the browser's locale
        const formattedDate = dateTimeFormatter.format(new Date(rawDate));

        // Update the element with the formatted date
        this.dateTarget.innerHTML = formattedDate;
    }
}
