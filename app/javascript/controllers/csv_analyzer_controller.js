// app/javascript/controllers/csv_analyzer_controller.js
import { Controller } from "@hotwired/stimulus"
import { post } from '@rails/request.js' // Use rails/request.js for easier AJAX

export default class extends Controller {
    static targets = [ "fileInput", "output", "analyzeButton" ]
    static values = { url: String } // URL for the analyze_csv action

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
        this.analyzeButtonTarget.disabled = true // Disable button during analysis

        post(this.urlValue, { // Use the URL passed from the view
            body: formData,
            responseKind: 'json' // Expect JSON back
        })
            .then(response => {
                if (response.ok) {
                    response.json.then(data => {
                        this.displayResults(data)
                    })
                } else {
                    response.json.then(data => {
                        this.displayError(data.error || `Error: ${response.statusCode}`)
                    }).catch(() => {
                        // Fallback if JSON parsing fails on error response
                        this.displayError(`An unknown error occurred (Status: ${response.statusCode}).`)
                    })
                }
            })
            .catch(error => {
                console.error("CSV Analysis Error:", error)
                this.displayError("A network or unexpected error occurred.")
            })
            .finally(() => {
                this.analyzeButtonTarget.disabled = false // Re-enable button
                this.fileInputTarget.value = '' // Clear file input
            })
    }

    displayResults(data) {
        let html = '<h6>Detected Columns:</h6>'

        if (data.headers && data.headers.length > 0) {
            html += '<p><strong>Headers Found:</strong></p><ul class="pure-list">'
            data.headers.forEach((header, index) => {
                html += `<li><strong>${index}:</strong> ${header || '(empty)'}</li>`
            })
            html += '</ul><p>You can use header names or indices below.</p>'
        } else if (data.columns && data.columns.length > 0) {
            html += '<p><strong>First Row Data (No Headers Detected):</strong></p><ul class="pure-list">'
            data.columns.forEach(col => {
                html += `<li><strong>${col.index}:</strong> ${col.value || '(empty)'}</li>`
            })
            html += '</ul><p>Use column indices (0, 1, 2...) below.</p>'
        } else {
            html += '<p class="pure-alert">Could not detect columns or headers. The file might be empty or invalid.</p>'
        }

        this.outputTarget.innerHTML = html
    }

    displayError(message) {
        this.outputTarget.innerHTML = `<p class="pure-alert pure-alert-error">Analysis Failed: ${message}</p>`
    }
}