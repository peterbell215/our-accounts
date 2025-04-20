// /home/peter-bell/RubymineProjects/our-accounts/app/javascript/controllers/account_table_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    // Optional: Define static values or targets if needed later
    // static targets = [ "myElement" ]
    // static values = { url: String }

    connect() {
        console.log("AccountTableController connected to", this.element);
    }

    disconnect() {
        console.log("AccountTableController disconnected from", this.element);
    }
}