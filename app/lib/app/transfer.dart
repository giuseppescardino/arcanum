import 'dart:convert';
import 'dart:typed_data';

import '../src/rust/api/transfer.dart' as rust;
import '../src/rust/api/transfer.dart' show ImportData;
import '../src/rust/api/vault.dart' show ItemFields;

export '../src/rust/api/transfer.dart' show ImportData, ImportFormat;

/// File formats for import and export. Implemented in Rust; swappable so
/// widget tests can run without the native library.
abstract class Transfer {
  /// Plaintext CSV in the browsers' column layout.
  Future<String> exportCsv(List<ItemFields> items);

  /// Backup encrypted with [password].
  Future<Uint8List> exportBackup(List<ItemFields> items, String password);

  /// Reads an Arcanum, browser, Bitwarden, 1Password or KeePass export.
  /// An encrypted backup read without [password] fails with
  /// `VaultFailureCode.backupPasswordRequired`.
  Future<ImportData> parse(Uint8List data, {String? password});
}

class RustTransfer implements Transfer {
  const RustTransfer();

  @override
  Future<String> exportCsv(List<ItemFields> items) =>
      rust.exportCsv(items: items);

  @override
  Future<Uint8List> exportBackup(List<ItemFields> items, String password) =>
      rust.exportBackup(items: items, password: utf8.encode(password));

  @override
  Future<ImportData> parse(Uint8List data, {String? password}) =>
      rust.parseImport(
        data: data,
        password: password == null ? null : utf8.encode(password),
      );
}

Transfer transfer = const RustTransfer();
