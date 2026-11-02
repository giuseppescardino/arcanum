//! Account Key → Vault Key → Item Key → item, each link bound to its
//! identifiers so the server cannot move, swap or replay ciphertexts.

use zeroize::Zeroizing;

use crate::{aead, Aad, Result, SymmetricKey};

const VAULT_KEY_LABEL: &str = "pm/vault-key/v1";
const ITEM_KEY_LABEL: &str = "pm/item-key/v1";
const ITEM_LABEL: &str = "pm/item/v1";

pub fn wrap_key(kek: &SymmetricKey, key: &SymmetricKey, aad: &Aad) -> Result<Vec<u8>> {
    aead::seal(kek, key.as_bytes(), aad)
}

pub fn unwrap_key(kek: &SymmetricKey, wrapped: &[u8], aad: &Aad) -> Result<SymmetricKey> {
    let raw = aead::open(kek, wrapped, aad)?;
    SymmetricKey::from_slice(&raw)
}

pub fn wrap_vault_key(
    account_key: &SymmetricKey,
    vault_id: &[u8],
    vault_key: &SymmetricKey,
) -> Result<Vec<u8>> {
    wrap_key(account_key, vault_key, &vault_key_aad(vault_id))
}

pub fn unwrap_vault_key(
    account_key: &SymmetricKey,
    vault_id: &[u8],
    wrapped: &[u8],
) -> Result<SymmetricKey> {
    unwrap_key(account_key, wrapped, &vault_key_aad(vault_id))
}

pub fn wrap_item_key(
    vault_key: &SymmetricKey,
    vault_id: &[u8],
    item_id: &[u8],
    item_key: &SymmetricKey,
) -> Result<Vec<u8>> {
    wrap_key(vault_key, item_key, &item_key_aad(vault_id, item_id))
}

pub fn unwrap_item_key(
    vault_key: &SymmetricKey,
    vault_id: &[u8],
    item_id: &[u8],
    wrapped: &[u8],
) -> Result<SymmetricKey> {
    unwrap_key(vault_key, wrapped, &item_key_aad(vault_id, item_id))
}

/// `revision` is the item's client-side revision counter; binding it
/// prevents the server from serving an older ciphertext as the current one.
pub fn encrypt_item(
    item_key: &SymmetricKey,
    vault_id: &[u8],
    item_id: &[u8],
    revision: u64,
    plaintext: &[u8],
) -> Result<Vec<u8>> {
    aead::seal(item_key, plaintext, &item_aad(vault_id, item_id, revision))
}

pub fn decrypt_item(
    item_key: &SymmetricKey,
    vault_id: &[u8],
    item_id: &[u8],
    revision: u64,
    ciphertext: &[u8],
) -> Result<Zeroizing<Vec<u8>>> {
    aead::open(item_key, ciphertext, &item_aad(vault_id, item_id, revision))
}

fn vault_key_aad(vault_id: &[u8]) -> Aad {
    Aad::new(VAULT_KEY_LABEL).field(vault_id)
}

fn item_key_aad(vault_id: &[u8], item_id: &[u8]) -> Aad {
    Aad::new(ITEM_KEY_LABEL).field(vault_id).field(item_id)
}

fn item_aad(vault_id: &[u8], item_id: &[u8], revision: u64) -> Aad {
    Aad::new(ITEM_LABEL)
        .field(vault_id)
        .field(item_id)
        .u64(revision)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::CryptoError;

    const VAULT: &[u8] = b"vault-1";
    const ITEM: &[u8] = b"item-1";

    #[test]
    fn full_chain_round_trip() {
        let account_key = SymmetricKey::generate().unwrap();
        let vault_key = SymmetricKey::generate().unwrap();
        let item_key = SymmetricKey::generate().unwrap();

        let wvk = wrap_vault_key(&account_key, VAULT, &vault_key).unwrap();
        let wik = wrap_item_key(&vault_key, VAULT, ITEM, &item_key).unwrap();
        let ct = encrypt_item(&item_key, VAULT, ITEM, 3, b"{\"password\":\"s3cr3t\"}").unwrap();

        let vk = unwrap_vault_key(&account_key, VAULT, &wvk).unwrap();
        let ik = unwrap_item_key(&vk, VAULT, ITEM, &wik).unwrap();
        let pt = decrypt_item(&ik, VAULT, ITEM, 3, &ct).unwrap();
        assert_eq!(&*pt, b"{\"password\":\"s3cr3t\"}");
    }

    #[test]
    fn item_cannot_be_moved_to_another_vault_or_id() {
        let ik = SymmetricKey::generate().unwrap();
        let ct = encrypt_item(&ik, VAULT, ITEM, 1, b"x").unwrap();
        assert_eq!(
            decrypt_item(&ik, b"vault-2", ITEM, 1, &ct),
            Err(CryptoError::Decrypt)
        );
        assert_eq!(
            decrypt_item(&ik, VAULT, b"item-2", 1, &ct),
            Err(CryptoError::Decrypt)
        );
    }

    #[test]
    fn old_revision_cannot_be_replayed() {
        let ik = SymmetricKey::generate().unwrap();
        let old = encrypt_item(&ik, VAULT, ITEM, 1, b"old").unwrap();
        assert_eq!(
            decrypt_item(&ik, VAULT, ITEM, 2, &old),
            Err(CryptoError::Decrypt)
        );
    }

    #[test]
    fn item_keys_cannot_be_swapped() {
        let vk = SymmetricKey::generate().unwrap();
        let wik = wrap_item_key(&vk, VAULT, ITEM, &SymmetricKey::generate().unwrap()).unwrap();
        assert_eq!(
            unwrap_item_key(&vk, VAULT, b"item-2", &wik),
            Err(CryptoError::Decrypt)
        );
    }

    #[test]
    fn item_key_is_not_a_valid_item_ciphertext() {
        // Domain separation: a wrapped key must never decrypt as an item.
        let k = SymmetricKey::generate().unwrap();
        let wik = wrap_item_key(&k, VAULT, ITEM, &SymmetricKey::generate().unwrap()).unwrap();
        assert_eq!(
            decrypt_item(&k, VAULT, ITEM, 0, &wik),
            Err(CryptoError::Decrypt)
        );
    }
}
