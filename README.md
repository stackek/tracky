<div align="center">
<img src="./assets/icon/logo.png" width="20%" alt="Tracky icon" />
</div>

# Tracky

A free, open source, privacy-first expense tracker for Android, written in
Flutter.

There are **no payments, subscriptions, ads, analytics or accounts**. The app
has no network permission and stores everything locally.

Tracky is compatible with My Expenses backups, so existing `.zip` and `.enc`
backups can be restored without losing data.

## Features

- Multiple accounts (cash, bank, credit card, asset, liability, investment)
  with opening balances, colours, favourites and archiving.
- Expenses, income, transfers between accounts (including different
  currencies) and split transactions.
- Hierarchical expense and income categories with colours and icons.
- Payees, payment methods and tags.
- Receipt and photo attachments.
- Fast transaction entry with search, account filters, date ranges, category,
  payee, tag, amount and void filters.
- Statistics with selectable accounts and date ranges, income/expense totals,
  spending by category and a six-month comparison chart.
- Monthly budgets with per-category allocations and progress.
- Reusable transaction templates.
- CSV export and import for spreadsheets.
- Full backup and restore, including encrypted backups and My Expenses backup
  compatibility.
- Material 3 interface with light, dark and system themes.

## Backup compatibility

Tracky reads and writes the My Expenses backup format. A backup is a ZIP file
containing:

```
BACKUP                          SQLite database
BACKUP_PREF                     Android shared preferences XML
ui_settings.preferences_pb      optional DataStore preferences
Pictures/<attachment-id>_<name> receipt pictures
```

- **Restore** accepts ordinary `.zip` backups and password-protected `.enc`
  backups. For encrypted backups Tracky asks for the password and decrypts
  them locally with AES-256-GCM.
- **Export** produces a standard backup ZIP. A fresh database is created with
  schema version 183.
- Receipt pictures keep the `<attachments._id>_<filename>` naming convention,
  so they are restored correctly.
- Preferences such as the home currency and theme are read from `BACKUP_PREF`;
  unknown preferences are preserved for future exports.

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
- `sqflite` with a backup-compatible schema.
- Repository layer in `lib/data/`, domain models in `lib/models/`, screens in
  `lib/screens/`.
- No network calls, no third-party SDKs, no telemetry.

## Licence

GNU General Public License v3.0. See [LICENSE](LICENSE).
