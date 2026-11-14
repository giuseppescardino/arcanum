import '../src/rust/api/vault.dart';

extension ItemFieldsCopy on ItemFields {
  /// Copy with the given fields replaced. `expiresOn` uses a sentinel-free
  /// pair: pass `clearExpiry: true` to remove it.
  ItemFields copyWith({
    String? password,
    String? group,
    bool? favorite,
    String? expiresOn,
    bool clearExpiry = false,
  }) => ItemFields(
    kind: kind,
    title: title,
    username: username,
    password: password ?? this.password,
    urls: urls,
    notes: notes,
    totp: totp,
    favorite: favorite ?? this.favorite,
    group: group ?? this.group,
    color: color,
    wifi: wifi,
    card: card,
    expiresOn: clearExpiry ? null : (expiresOn ?? this.expiresOn),
  );
}
