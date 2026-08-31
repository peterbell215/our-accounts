import { Controller } from "@hotwired/stimulus"

// Hidden rather than removed, so the delete button beside it does not move when it appears.
const UNCHANGED_CLASS = "is-unchanged"

// Keeps the save button out of the way until the row has an edit to save.
//
// Every row is a form of its own and the only field a saved transaction exposes is its category, so
// most rows on screen are never edited and their save button means nothing.
//
// What counts as an edit is read back off the fields themselves each time — `defaultValue` and
// `defaultSelected` hold what the server rendered — rather than being remembered here. The list
// detaches rows that scroll out of its window and re-attaches them later, which disconnects and
// reconnects this controller over an edit the reader has not saved yet; recomputing from the fields
// survives that, where a flag on the instance would not.
export default class extends Controller {
    static targets = [ "save", "description", "counterparty" ]
    static values = {
        // A row that has never been saved always has something to save.
        unsaved: { type: Boolean, default: false },
        // A row whose counterparty name is waiting to be confirmed also has: the reader has to press save a
        // second time to create it. Nothing on the row looks edited at that point — the server has just
        // rendered the typed name as the field's default, and the hidden field carrying the confirmation is
        // filtered out below — so without this the button the reader needs would be hidden.
        pending: { type: Boolean, default: false }
    }

    connect() {
        this.refresh()
    }

    // Offered only where no counterparty is set yet (see the row partial), so this never overwrites one.
    // Dispatching "input" rather than calling #refresh directly is what marks the row changed: it bubbles
    // to the form's own input listener the same way a reader's keystroke would.
    copyDescriptionToCounterparty() {
        const description = this.descriptionTarget.value ?? this.descriptionTarget.textContent

        this.counterpartyTarget.value = description.trim()
        this.counterpartyTarget.dispatchEvent(new Event("input", { bubbles: true }))
        this.counterpartyTarget.focus()
    }

    refresh() {
        this.saveTarget.classList.toggle(UNCHANGED_CLASS, !this.changed)
    }

    get changed() {
        if (this.unsavedValue || this.pendingValue) return true

        return this.fields.some(field => (
            field.tagName === "SELECT" ? this.selectChanged(field) : field.value !== field.defaultValue
        ))
    }

    // The fields the reader can actually edit: the token and method inputs Rails adds never change.
    get fields() {
        return Array.from(this.element.elements).filter(field => (
            [ "INPUT", "SELECT", "TEXTAREA" ].includes(field.tagName) &&
            ![ "hidden", "submit", "button" ].includes(field.type)
        ))
    }

    // With nothing marked selected the browser picks the first option, which is the blank one.
    selectChanged(select) {
        const rendered = Array.from(select.options).find(option => option.defaultSelected)

        return select.value !== (rendered ? rendered.value : "")
    }
}
