## 1. Widget Coverage

- [ ] 1.1 Add a failing Settings widget test that opens Advanced git args and verifies the args input starts empty with example hint text.
- [ ] 1.2 Add a failing Settings widget test that pressing Run with untouched empty input does not call `runArgs` and shows the existing empty-args validation message.
- [ ] 1.3 Update the existing failed-output Settings test to type `status --bad` before expecting the selected command preview and Git output.

## 2. Settings UI Implementation

- [ ] 2.1 Change the Advanced git args sheet state so `argsText` starts empty.
- [ ] 2.2 Replace the prefilled `status` value with placeholder/hint text such as `status, log`.
- [ ] 2.3 Ensure command preview and run behavior are based only on typed input, preserving current validation for empty input.

## 3. Verification

- [ ] 3.1 Run the focused Settings widget tests covering Advanced git args.
- [ ] 3.2 Run `flutter analyze`.
- [ ] 3.3 Run `openspec validate hint-advanced-git-args --strict`.
