import 'dart:io';

import 'package:flutter/services.dart';

class BackupDirectory {
  const BackupDirectory({required this.uri, required this.label});

  final String uri;
  final String label;
}

class StorageAccess {
  static const _channel = MethodChannel('com.stackek.tracky/storage');

  static bool get isSupported => Platform.isAndroid;

  static Future<BackupDirectory?> pickDirectory({String? initialUri}) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickDirectory',
      {'initialUri': initialUri},
    );
    if (result == null) return null;
    final uri = result['uri'] as String?;
    final label = result['label'] as String?;
    if (uri == null || label == null) return null;
    return BackupDirectory(uri: uri, label: label);
  }

  static Future<void> writeFile({
    required String uri,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    await _channel.invokeMethod<void>('writeFile', {
      'uri': uri,
      'fileName': fileName,
      'mimeType': mimeType,
      'bytes': bytes,
    });
  }
}
