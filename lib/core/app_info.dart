const appName = 'Tracky';
const appVersion = '1.0.0';
const appBuildNumber = 1;
const appVersionLabel = 'Version $appVersion';
const repositoryUrl = 'https://github.com/stackek/tracky';
const releasesUrl = '$repositoryUrl/releases';

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
