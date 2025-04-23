import { Controller } from "@hotwired/stimulus"

// Formatter for display (e.g., "July 20, 2024")
const displayDateTimeFormatter = new Intl.DateTimeFormat(navigator.language, {
    year: "numeric",
    month: "long",
    day: "numeric",
});

// Helper to format date as YYYY-MM-DD for input fields
function formatDateForInput(date) {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0'); // Months are 0-indexed
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
}

export default class extends Controller {
    static targets = [ "date" ];

    connect() {
        this.dateTargets.forEach(targetElement => {
            const rawDateString = targetElement.dataset.date;
            if (!rawDateString) return; // Skip if no date data

            const dateObject = new Date(rawDateString);
            if (isNaN(dateObject)) return; // Skip if the date is invalid

            // Try to find a span or an input within the target div
            const spanElement = targetElement.querySelector('span');
            const inputElement = targetElement.querySelector('input[type="date"]');

            if (spanElement) {
                // If a span exists (display mode for persisted transaction), format for display
                const formattedDisplayDate = displayDateTimeFormatter.format(dateObject);
                spanElement.textContent = formattedDisplayDate; // Update the span's text
            }
        });
    }
}
