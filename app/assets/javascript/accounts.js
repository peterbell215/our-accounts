document.addEventListener("DOMContentLoaded", function() {
    const accountType = document.getElementById("type");
    const sortcodeField = document.getElementById("sortcode");

    function toggleSortcodeField() {
        if (accountType.value === "CreditCard") {
            sortcodeField.style.display = "none";
        } else {
            sortcodeField.style.display = "";
        }
    }

    accountType.addEventListener("change", toggleSortcodeField);

    // Initial check
    toggleSortcodeField();
});
