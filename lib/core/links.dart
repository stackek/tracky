import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';

Future<void> openReleasesPage(BuildContext context) async {
  await _open(context, releasesUrl);
}

Future<void> openRepositoryPage(BuildContext context) async {
  await _open(context, repositoryUrl);
}

Future<void> openLicencePage(BuildContext context) async {
  await _open(context, licenceUrl);
}

Future<void> _open(BuildContext context, String url) async {
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
  }
}
