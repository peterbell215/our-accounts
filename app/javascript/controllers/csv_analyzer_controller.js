// app/javascript/controllers/csv_analyzer_controller.js
import { Controller } from "@hotwired/stimulus"
import { post } from '@rails/request.js'

export default class extends Controller {
    // Add dropZone target for the input fields in the main form
    static targets = [ "fileInput", "output", "analyzeButton", "dropZone" ]
    static values = { url: String }

    // CSS class for visual feedback on drop targets
    static classes = [ "dragOver" ] // e.g., data-csv-analyzer-drag-over-class="drag-over"

    analyze(event) {
        event.preventDefault()
        const file = this.fileInputTarget.files[0]

        if (!file) {
            this.outputTarget.innerHTML = `<p class="pure-alert pure-alert-warning">Please select a CSV file first.</p>`
            return
        }

        const formData = new FormData()
        formData.append("csv_file", file)

        this.outputTarget.innerHTML = `<p>Analyzing...</p>`
        this.analyzeButtonTarget.disabled = true

        post(this.urlValue, {
            body: formData,
            responseKind: 'json'
        })
            .then(response => {
                if (response.ok) {
                    return response.json // Pass the parsed JSON promise
                } else {
                    // Try to parse error JSON, otherwise throw generic error
                    return response.json.then(data => {
                        throw new Error(data.error || `Error: ${response.statusCode}`)
                    }).catch(() => {
                        throw new Error(`An unknown error occurred (Status: ${response.statusCode}).`)
                    })
                }
            })
            .then(data => { // Handle successful JSON data
                this.displayResults(data)
            })
            .catch(error => { // Catch errors from the fetch or thrown above
                console.error("CSV Analysis Error:", error)
                this.displayError(error.message || "A network or unexpected error occurred.")
            })
            .finally(() => {
                this.analyzeButtonTarget.disabled = false
                // Don't clear file input immediately, user might want to re-analyze
                // this.fileInputTarget.value = ''
            })
    }

    displayResults(data) {
        let html = '<h6>Detected Columns (Drag to map):</h6>' // Updated title

        if (data.headers && data.headers.length > 0) {
            html += '<p><strong>Headers Found:</strong></p><ul class="pure-list">'
            data.headers.forEach((header, index) => {
                const columnValue = header || `Column ${index}` // Use header name if available, otherwise fallback
                // Add draggable="true", data-action for dragstart, and data-column-value
                html += `<li draggable="true"
                           data-action="dragstart->csv-analyzer#handleDragStart"
                           data-column-value="${this.escapeHtml(columnValue)}"> <!-- Store the value to drag -->
                          <strong>${index}:</strong> ${header || '(empty)'}
                       </li>`
            })
            html += '</ul><p>Drag header names or indices to fields.</p>'
        } else if (data.columns && data.columns.length > 0) {
            html += '<p><strong>First Row Data (No Headers Detected):</strong></p><ul class="pure-list">'
            data.columns.forEach(col => {
                const columnValue = col.index.toString() // Use index as the value to drag
                // Add draggable="true", data-action for dragstart, and data-column-value
                html += `<li draggable="true"
                            data-action="dragstart->csv-analyzer#handleDragStart"
                            data-column-value="${columnValue}"> <!-- Store the index -->
                           <strong>${col.index}:</strong> ${col.value || '(empty)'}
                        </li>`
            })
            html += '</ul><p>Drag column indices (0, 1, 2...) to fields.</p>'
        } else {
            html += '<p class="pure-alert">Could not detect columns or headers. The file might be empty or invalid.</p>'
        }

        this.outputTarget.innerHTML = html
    }

    displayError(message) {
        this.outputTarget.innerHTML = `<p class="pure-alert pure-alert-error">Analysis Failed: ${message}</p>`
    }

    // --- Drag and Drop Event Handlers ---

    handleDragStart(event) {
        // Get the value (header name or index) stored in the data attribute
        const columnValue = event.currentTarget.dataset.columnValue
        // Set the data to be transferred
        event.dataTransfer.setData("text/plain", columnValue)
        event.dataTransfer.effectAllowed = "copy"; // Indicate the type of operation
        // Optional: Add a class to the dragged element for styling
        // event.currentTarget.classList.add('dragging');
    }

    handleDragOver(event) {
        // Prevent default behavior (which is usually disallowed for dropping)
        event.preventDefault();
        // Indicate this is a valid drop target
        event.dataTransfer.dropEffect = "copy";
        // Add visual feedback class to the drop zone (the input field)
        event.currentTarget.classList.add("drag-over"); // Use Stimulus class
    }

    handleDragLeave(event) {
        // Remove visual feedback class when dragging leaves the drop zone
        event.currentTarget.classList.remove("drag-over");
    }

    handleDrop(event) {
        // Prevent default behavior (like opening link for text/plain)
        event.preventDefault();
        // Remove visual feedback class
        event.currentTarget.classList.remove("drag-over");
        // Get the data that was set during dragstart
        const columnValue = event.dataTransfer.getData("text/plain");
        // Set the value of the drop target (the input field)
        event.currentTarget.value = columnValue;

        // Optional: Trigger change event if needed by other JS/Rails UJS
        event.currentTarget.dispatchEvent(new Event('change', { bubbles: true }));
    }

    // Helper to prevent basic HTML injection issues when setting data attributes
    escapeHtml(unsafe) {
        if (!unsafe) return "";
        return unsafe
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
    }
}
