# Changelog

## 1.1.0 - 2026-10-21

- Automatic backups now use Android's folder picker and work with scoped storage.
- Removed My Expenses-only database fields and tables; account and payee data simplified.
- Default account types are Cash and Card.
- Transactions can be split while keeping the expense, income and transfer controls.
- Foldable days in the transaction list, parent category selection and tag remapping.
- Multiple tags per transaction are supported throughout the app.
- Statistics can expand categories recursively into subcategories with distinct colours.
- Debts are now simple containers: assigned transactions appear in them and change their balance.
- Transfers are shown once in the all-accounts view and can be deleted again.
- Added transaction counts to tags, payees and account types.
- The licence entry in About opens the project licence on GitHub.
- Added a demo backup for testing.

## 1.0.1 - 2026-10-21

First F-Droid release of Tracky.

- New application ID: `com.stackek.tracky`.
- Added F-Droid build metadata and Fastlane store listing.
- Added in-app changelog, source code and release links.

## 1.0.0 - 2026-10-21

First public release of Tracky.

- Accounts, transactions, transfers and split transactions.
- Statistics with selectable accounts and custom date ranges.
- Budgets, templates, tags, payees and receipt attachments.
- Encrypted backup and restore, plus CSV export and import.
- Compatible with My Expenses backups.
