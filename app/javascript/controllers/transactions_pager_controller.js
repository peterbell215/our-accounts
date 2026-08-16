import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

// Loads the next page of transactions when the end of the list comes into view.
//
// The controller is attached to the end-of-table marker.  Fetching returns a Turbo Stream that appends
// the rows and replaces this element with a fresh marker, so this instance is torn down and the next one
// takes over; when the history runs out the replacement carries no controller and the loading stops.
export default class extends Controller {
    static values = { url: String }

    connect() {
        // A margin so the next page starts loading just before the reader reaches the bottom.
        this.observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting)) this.load()
            },
            { rootMargin: "300px" }
        )
        this.observer.observe(this.element)
    }

    disconnect() {
        this.observer?.disconnect()
        this.observer = null
    }

    async load() {
        if (this.loading) return
        this.loading = true

        // Stop observing straight away: this element is about to be replaced, and a second request for
        // the same cursor would duplicate the rows.
        this.observer?.disconnect()

        await get(this.urlValue, { responseKind: "turbo-stream" })
    }
}
