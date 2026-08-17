import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

// Keeps a long transaction list to a fixed number of rendered rows.
//
// Every row that has been fetched is held in `this.rows`, but only a window of `size` of them is in the
// document at any moment. Scrolling to either edge of the scroll box slides the window by `step`: rows
// leaving the window are detached rather than discarded, so scrolling back re-attaches the same elements
// — no second request, and anything the reader had typed or selected in them survives.
//
// Sliding the window changes the height above the visible rows, so scrollTop is adjusted by the same
// amount afterwards; without that the content jumps under the reader's cursor.
export default class extends Controller {
    static values = {
        size: { type: Number, default: 20 },
        step: { type: Number, default: 10 },
        start: { type: Number, default: 0 },
        // Counts requests made, so a test can prove that scrolling back up fetches nothing.
        fetches: { type: Number, default: 0 }
    }

    connect() {
        this.rows = Array.from(this.rowElements())
        this.startValue = 0
        this.render()

        this.onScroll = () => this.scheduleCheck()
        this.element.addEventListener("scroll", this.onScroll, { passive: true })
    }

    disconnect() {
        this.element.removeEventListener("scroll", this.onScroll)
    }

    // --- DOM handles ---------------------------------------------------------------------------------

    get body() {
        return this.element.querySelector("#transactions_div_body")
    }

    get marker() {
        return this.element.querySelector("#end-of-table-marker")
    }

    get nextUrl() {
        const url = this.marker?.dataset.nextUrl
        return url && url.length > 0 ? url : null
    }

    rowElements() {
        return this.body.querySelectorAll(".transaction-row")
    }

    // --- scrolling -----------------------------------------------------------------------------------

    scheduleCheck() {
        if (this.checkQueued) return
        this.checkQueued = true

        requestAnimationFrame(() => {
            this.checkQueued = false
            this.check()
        })
    }

    check() {
        const box = this.element
        const threshold = 40

        if (box.scrollTop + box.clientHeight >= box.scrollHeight - threshold) {
            this.forward()
        } else if (box.scrollTop <= threshold) {
            this.backward()
        }
    }

    async forward() {
        // At the end of what has been fetched, ask for more before sliding.
        if (this.startValue + this.sizeValue >= this.rows.length) {
            if (!(await this.fetchMore())) return
        }

        this.slideTo(Math.min(this.startValue + this.stepValue,
                              Math.max(0, this.rows.length - this.sizeValue)))
    }

    backward() {
        this.slideTo(Math.max(0, this.startValue - this.stepValue))
    }

    // Moves the window and keeps the rows under the reader's eye where they were.
    slideTo(start) {
        if (start === this.startValue) return

        const rowHeight = this.rowHeight()
        const moved = start - this.startValue

        this.startValue = start
        this.render()
        this.element.scrollTop -= moved * rowHeight
    }

    // --- rendering -----------------------------------------------------------------------------------

    render() {
        const visible = this.rows.slice(this.startValue, this.startValue + this.sizeValue)
        const keep = new Set(visible)
        const marker = this.marker

        // Detach the buffered rows that fall outside the window. Rows that are not in the buffer — an
        // unsaved row from "Add New Transaction" — are left where they are.
        for (const row of this.rows) {
            if (!keep.has(row) && row.isConnected) row.remove()
        }

        for (const row of visible) {
            if (row.nextElementSibling !== marker || !row.isConnected) {
                this.body.insertBefore(row, marker)
            }
        }
    }

    // Rows are a single line each, so one measurement stands for all of them.
    rowHeight() {
        return this.rows[this.startValue]?.offsetHeight || 40
    }

    // --- fetching ------------------------------------------------------------------------------------

    // @return {Promise<boolean>} whether any new rows were added
    async fetchMore() {
        if (this.loading || !this.nextUrl) return false
        this.loading = true

        try {
            const response = await get(this.nextUrl, { responseKind: "html" })
            if (!response.ok) return false

            const holder = document.createElement("div")
            holder.innerHTML = await response.text
            const fragment = holder.querySelector("[data-rows]")
            if (!fragment) return false

            const fetched = Array.from(fragment.querySelectorAll(".transaction-row"))
            this.rows.push(...fetched)
            this.marker.dataset.nextUrl = fragment.dataset.nextUrl || ""
            this.fetchesValue = this.fetchesValue + 1

            return fetched.length > 0
        } finally {
            this.loading = false
        }
    }
}
