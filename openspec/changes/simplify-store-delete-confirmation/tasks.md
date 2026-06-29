## 1. Bridge Validation

- [x] 1.1 Add or update bridge/store lifecycle tests showing delete-local-store accepts the final store name as confirmation.
- [x] 1.2 Add or update bridge/store lifecycle tests showing mismatched confirmation fails without deleting files.
- [x] 1.3 Change `delete_local_store_inner` to derive the expected confirmation from the normalized root basename while preserving configured-root, existing-directory, and filesystem-root safeguards.
- [x] 1.4 Update delete-local-store validation error text to ask for the store name rather than the full root.

## 2. Flutter Settings UI

- [x] 2.1 Add or update settings widget coverage for deleting a local store by typing only the displayed store name.
- [x] 2.2 Update the delete local store sheet to show the full root as read-only context and label the confirmation field with the required store name.
- [x] 2.3 Ensure the repository request still sends the selected root as the deletion target and sends the user's store-name confirmation unchanged.

## 3. Repository and Fixture Updates

- [x] 3.1 Update bridge-backed repository tests and fake repository expectations from full-root confirmation to store-name confirmation where they model local store deletion.
- [x] 3.2 Confirm generated bridge bindings do not need regeneration because the request schema remains `root` plus `confirmation`.

## 4. Verification

- [x] 4.1 Run focused Rust/bridge tests covering delete-local-store behavior.
- [x] 4.2 Run focused Flutter widget tests covering settings store deletion confirmation.
- [x] 4.3 Run `flutter analyze` from `gui`.
- [x] 4.4 Run `flutter test` from `gui`.
- [x] 4.5 Run `openspec validate simplify-store-delete-confirmation --strict`.
