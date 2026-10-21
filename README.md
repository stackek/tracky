# My Expenses Open

A free, open source, privacy-first expense tracker for Android, written in
Flutter. It is designed as a modern replacement for
[My Expenses](https://github.com/mtotschnig/MyExpenses) and can restore backups
created by My Expenses without losing data.

There are **no payments, subscriptions, ads, analytics or accounts**. The app
has no network permission and stores everything locally.

## Features

- Multiple accounts (cash, bank, credit card, asset, liability, investment)
  with opening balances, colours, favourites and archiving.
- Expenses, income, transfers between accounts (including different
  currencies) and split transactions.
- Hierarchical expense and income categories with colours and icons.
- Payees, payment methods and tags.
- Receipt and photo attachments.
- Fast transaction entry with search, account filters, date ranges, category
  and payee filters.
- Statistics: monthly income/expense/net, spending by category and a six-month
  comparison chart.
- Monthly budgets with per-category allocations and progress.
- Reusable transaction templates.
- CSV export and import for spreadsheets.
- Full backup and restore, compatible with My Expenses backups.
- Material 3 interface with light, dark and system themes.

## Backup compatibility

A My Expenses backup is a ZIP file containing:

```
BACKUP                          SQLite database
BACKUP_PREF                     Android shared preferences XML
ui_settings.preferences_pb      optional DataStore preferences
Pictures/<attachment-id>_<name> receipt pictures
```

This app reads and writes exactly that format:

- **Restore** accepts ordinary `.zip` backups and password protected `.enc`
  backups. Encrypted backups use the same algorithm as My Expenses:
  AES-256-GCM, key = SHA-256(password), 12-byte nonce, magic `ME_ENC_01`.
- **Export** produces a standard My Expenses ZIP. A fresh database is created
  with My Expenses schema version 183, which both older and current My Expenses
  releases can open and upgrade. Imported databases keep their original schema
  version.
- Receipt pictures are stored with the `<attachments._id>_<filename>` naming
  convention expected by My Expenses, so they are restored on both sides.
- Preferences such as the home currency and theme are read from
  `BACKUP_PREF`; unknown preferences are preserved for future exports.

The test backup `myexpenses-backup-20261017-000003.zip` created by My Expenses
was used to validate the importer.

## Development with Nix

Everything needed is declared in `flake.nix`; no global Nix configuration needs
to be changed. The shell creates a small writable overlay of the immutable Nix
Android SDK so Flutter 3.47 can find the bundled NDK.

```sh
nix develop
flutter pub get
flutter analyze
flutter build apk --release
```

The APK is written to:

```
build/app/outputs/flutter-apk/app-release.apk
```

The Gradle and Pub caches are kept inside the project (`.gradle/`,
`.pub-cache/`) so nothing is written to the user's home directory by the
development shell.

## Architecture

- Flutter + Material 3, Riverpod for state, go_router for navigation.
- `sqflite` with the original My Expenses schema. Using the same schema makes
  migration lossless and keeps backup export bidirectional.
- Repository layer in `lib/data/`, domain models in `lib/models/`, screens in
  `lib/screens/`.
- No network calls, no third-party SDKs, no telemetry.

## Implemented compared with My Expenses

Implemented: accounts, transactions, transfers, splits, categories, payees,
payment methods, tags, attachments, filters, statistics, budgets, templates,
CSV, backup/restore, multiple currencies, themes.

Not implemented (yet): bank sync (WebDAV/Dropbox/Google Drive/OneDrive),
FinTS/HBCI, home screen widgets, OCR, calendar-based recurring plan execution,
QIF, automatic exchange-rate downloads, and full multi-currency conversion in
aggregate statistics. Backups containing this data are still restored and
exported without losing it.

## Licence

GNU General Public License v3.0. See [LICENSE](LICENSE).

My Expenses is a separate project by Michael Totschnig and contributors; this
project is an independent, compatible implementation. The My Expenses schema
and backup design are reused for interoperability.
