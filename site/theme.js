// Runs before first paint so a stored light or dark choice does not flash the other printing.
try {
    const stored = localStorage.getItem("misra-zig-theme");
    if (stored === "light" || stored === "dark") document.documentElement.dataset.theme = stored;
} catch (err) {
    // Storage can be disabled; the page then follows the system setting. The failure is logged so it is not silent.
    console.warn("theme: localStorage unavailable, using system setting", err);
}
