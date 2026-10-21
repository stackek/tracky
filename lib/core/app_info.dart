const appName = 'Tracky';
const appVersion = '1.1.0';
const appBuildNumber = 3;
const appVersionLabel = 'Version $appVersion';
const repositoryUrl = 'https://github.com/stackek/tracky';
const releasesUrl = '$repositoryUrl/releases';
const licenceUrl = '$repositoryUrl/blob/main/LICENSE';

class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });

  final String version;
  final String date;
  final List<String> changes;
}

const changelogEntries = <ChangelogEntry>[
  ChangelogEntry(
    version: appVersion,
    date: '21 October 2026',
    changes: [
      'Automatic backups now use the Android folder picker.',
      'Removed unused My Expenses fields and simplified accounts and payees.',
      'Foldable transaction days, parent category selection and tag remapping.',
      'Recursive statistics breakdown with distinct subcategory colours.',
      'Simplified debts: assigned transactions directly change the balance.',
      'Fixed transfer display and deletion.',
      'Added transaction counts for tags, payees and account types.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.1',
    date: '21 October 2026',
    changes: [
      'First F-Droid release of Tracky.',
      'New application ID: com.stackek.tracky.',
      'Added in-app changelog, source code and release links.',
    ],
  ),
  ChangelogEntry(
    version: '1.0.0',
    date: '21 October 2026',
    changes: [
      'First public release of Tracky.',
      'Accounts, transactions, transfers and split transactions.',
      'Statistics with selectable accounts and custom date ranges.',
      'Budgets, templates, tags, payees and receipt attachments.',
      'Encrypted backup and restore, plus CSV export and import.',
      'Compatible with My Expenses backups.',
    ],
  ),
];

ChangelogEntry get latestChangelog => changelogEntries.first;
