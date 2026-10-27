// Runs before first paint so a stored light or dark choice does not flash the other printing.
try {
    const stored = localStorage.getItem("misra-zig-theme");
    if (stored === "light" || stored === "dark") document.documentElement.dataset.theme = stored;
} catch {
    // Storage can be disabled; the page then follows the system setting.
}
