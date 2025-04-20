import { Controller } from "@hotwired/stimulus"

const dateTimeFormatter = new Intl.DateTimeFormat(navigator.language, {
    year: "numeric",
    month: "long",
    day: "numeric",
});

export default class extends Controller {
    static targets = [ "date" ];

    connect() {
        // Loop through all elements marked as 'date' targets within this controller's scope (tbody)
        this.dateTargets.forEach(targetElement => {
            const rawDate = targetElement.dataset.date; // Get data from the target itself
            const formattedDate = dateTimeFormatter.format(new Date(rawDate));
            targetElement.innerHTML = formattedDate; // Update the target
        });
    }
}
