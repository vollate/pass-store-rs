## 1. Theme and Surface Corrections

- [x] 1.1 Audit all hand-written Flutter `TextField`, `TextFormField`, and input-like surfaces for hard-coded light fills; preserve and document intentional light-only output surfaces such as the QR-code background.
- [x] 1.2 Replace the entry detail password surface's hard-coded light fill with the active input/theme surface color and ensure its password text and reveal icon inherit compatible foreground colors.

## 2. Entry Detail Layout Stability

- [x] 2.1 Apply a state-independent full-width constraint to `EntryDetailSheet` so passphrase, loading, error, empty, and loaded branches request all width permitted by the modal route.
- [x] 2.2 Verify the width behavior remains adaptive under Material 3 phone and wider-screen modal constraints without introducing a fixed pixel width.

## 3. Regression Coverage and Validation

- [x] 3.1 Add widget tests using `ParsTheme.dark()` that assert the password surface and PGP passphrase input resolve theme-derived dark fills with legible foreground content.
- [x] 3.2 Add widget tests with controllable asynchronous reads that assert the modal width remains stable from loading to loaded and error states, including the passphrase-to-loading transition.
- [x] 3.3 Run Flutter formatting, static analysis, and the relevant GUI widget test suite; resolve any regressions.
