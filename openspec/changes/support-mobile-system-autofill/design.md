## Context

Pars mobile runtime already configures a pure Rust OpenPGP backend under the
application support directory, keeps a selected password store in app-managed
storage, and stores optional PGP passphrases in platform secure storage through
Flutter. Entry parsing recognizes the password first line plus common fields
such as username, login, email, url, and website.

System autofill has different process boundaries than the Flutter app. Android
invokes services declared in the app manifest. iOS invokes a Credential
Provider extension in a separate process and relies on shared app group data
plus AuthenticationServices credential identities.

## Goals / Non-Goals

**Goals:**

- Let users choose Pars as the system password manager on iOS and Android.
- Fill username and password for websites and apps after local authentication.
- Avoid persisting plaintext passwords in shared autofill data.
- Keep matching deterministic and explainable from existing pass entry fields.
- Let the main app refresh and clear autofill data from Settings.

**Non-Goals:**

- Save or update credentials from system save prompts.
- Implement passkeys, TOTP autofill, or notes autofill.
- Support autofill for stores other than the currently selected mobile store.
- Keep system autofill working when no local PGP session/passphrase cache can
  decrypt the requested entry.

## Decisions

1. **Use one shared Rust autofill core with native wrappers.**

   Matching, index parsing, entry lookup, and credential DTO formatting should
   live in Rust so Android, iOS, and Flutter use the same behavior. Flutter can
   call it through FRB, while Android and iOS call a small JSON-based native
   ABI from their service or extension process.

2. **Store metadata-only autofill indexes.**

   The index should contain entry path, display name, username-like fields,
   service identifiers, favorite/recent ranking, and freshness metadata. It
   must not contain passwords, raw notes, TOTP values, or full decrypted entry
   content. Passwords are decrypted only after the platform autofill request has
   been selected and authenticated.

3. **Make PGP passphrase available to read-entry operations.**

   The existing UI can start a key-bound PGP session, but bridge read requests
   do not receive the active passphrase. Read-entry requests should accept an
   optional passphrase and pass it through the configured backend. System
   autofill should use the key-bound cached passphrase only after biometric or
   device authentication.

4. **Use field-based service matching.**

   Website matching should use normalized hosts from `url`, `website`, or
   `service` fields. Android app matching should require an exact
   `android-package` or `android_package` field. If no service field exists,
   path and display-name fallback can provide lower-ranked manual candidates.

5. **Keep Settings as the control surface.**

   Settings should expose system autofill status, platform setup shortcuts,
   index refresh, and data clearing. On iOS, refreshing the index should also
   update `ASCredentialIdentityStore`; clearing data should remove identities.

6. **Use platform-shared storage only where required.**

   Android can read app-private files from services in the same package. iOS
   must move or mirror mobile runtime files needed by the extension into an app
   group container and share passphrase access through a keychain access group.

## Risks / Trade-offs

- **iOS app group and keychain groups require provisioning setup.** The code can
  declare entitlements, but final device builds require matching Apple
  developer configuration.
- **Autofill services cannot rely on Flutter UI state.** Native services must
  initialize Rust and platform storage independently, so duplicated lightweight
  bootstrap code is necessary.
- **Metadata-only indexing may miss entries without URL or package fields.**
  Path fallback keeps manual selection useful without weakening exact matching.
- **Passphrase caching is sensitive.** Autofill should fail closed when the
  cache is disabled, expired, mismatched, or local authentication fails.
