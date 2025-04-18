// app/javascript/controllers/csv_analyzer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = { url: String }
    static classes = [ "dragOver" ]
    static targets = [ "columnList" ] // Target for the list within the frame

    // --- Drag and Drop Event Handlers ---
    handleDragStart(event) {
        const columnValue = event.currentTarget.dataset.columnValue
        event.dataTransfer.setData("text/plain", columnValue)
        event.dataTransfer.effectAllowed = "copy";
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
        event.currentTarget.classList.add(this.dragOverClass);
    }

    handleDragLeave(event) {
        event.currentTarget.classList.remove(this.dragOverClass);
    }

    handleDrop(event) {
        event.preventDefault();
        event.currentTarget.classList.remove(this.dragOverClass);
        const columnValue = event.dataTransfer.getData("text/plain");
        event.currentTarget.value = columnValue;
        event.currentTarget.dispatchEvent(new Event('change', { bubbles: true }));
    }

    // connect/disconnect remain the same if needed for dropZone listeners
    connect() {
      console.log("CSV Analyzer Controller connected.");
    }
    disconnect() {
      console.log("CSV Analyzer Controller disconnected.");
     }

    // --- Custom Action Handlers ---
    resultsLoaded(event) {
        console.log("CSV analysis results loaded/updated via Turbo Stream.");
        // You can access the frame element via event.target if needed
        // You can access the columnList target via this.columnListTarget (if it exists after the update)
        // Check if the target exists before accessing dataset
        if (this.hasColumnListTarget) {
            const hasHeader = this.columnListTarget.dataset.hasHeader === 'true';
            console.log("Detected header status:", hasHeader);
            // Add logic here to update the checkbox based on hasHeader
        } else {
            console.log("columnList target not found after update.");
        }
    }
}
