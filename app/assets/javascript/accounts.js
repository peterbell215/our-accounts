document.addEventListener("DOMContentLoaded", function() {
    const accountType = document.getElementById("type");
    const sortcodeField = document.getElementById("sortcode");

    function toggleSortcodeField() {
        if (accountType.value === "CreditCardAccount") {
            sortcodeField.style.display = "none";
            sortcodeField.disabled = true;
        } else {
            sortcodeField.style.display = "";
            sortcodeField.disabled = false;
        }
    }

    accountType.addEventListener("change", toggleSortcodeField);

    // Initial check
    toggleSortcodeField();
});
