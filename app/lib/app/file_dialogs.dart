import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The system's open and save dialogs; swappable in tests.
abstract class FileDialogs {
  /// Whether this platform can save a file where the user chooses.
  bool get canSave;

  /// Contents of the file the user picked; null when they cancel.
  Future<Uint8List?> pickFile();

  /// Returns false when the user cancels.
  Future<bool> saveFile({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  });
}

class PlatformFileDialogs implements FileDialogs {
  const PlatformFileDialogs();

  static const _channel = MethodChannel('pm/platform');

  /// Larger files are certainly not a password export.
  static const _maxImportBytes = 64 * 1024 * 1024;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get canSave => !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

  @override
  Future<Uint8List?> pickFile() async {
    final file = await openFile();
    if (file == null) return null;
    if (await file.length() > _maxImportBytes) {
      throw const FileSystemException('File too large');
    }
    return file.readAsBytes();
  }

  @override
  Future<bool> saveFile({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (_isAndroid) {
      // Storage Access Framework: the user picks where the document goes.
      final saved = await _channel.invokeMethod<bool>('saveFile', {
        'name': name,
        'mimeType': mimeType,
        'bytes': bytes,
      });
      return saved ?? false;
    }
    final extension = name.substring(name.lastIndexOf('.') + 1);
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return false;
    await File(location.path).writeAsBytes(bytes, flush: true);
    return true;
  }
}

FileDialogs fileDialogs = const PlatformFileDialogs();
