//! Quick (biometric) unlock.
//!
//! The Account Key is wrapped with a random 256-bit secret that the app
//! keeps in the platform's biometric-protected store (Secure Enclave /
//! Android Keystore / Windows Hello-gated DPAPI). The master password is
//! still required at least every [`QUICK_UNLOCK_MAX_AGE_MS`], and any
//! password change disables quick unlock.

use arcanum_crypto::{hierarchy, Aad, SymmetricKey, KEY_LEN};
use rand_core::{OsRng, RngCore};
use zeroize::Zeroizing;

use crate::vault::{now_ms, wrong_credentials};
use crate::{Result, Vault, VaultError};

const META_QUICK_UNLOCK: &str = "quick_unlock";
const META_LAST_PASSWORD_UNLOCK: &str = "last_password_unlock";
const QUICK_UNLOCK_LABEL: &str = "pm/quick-unlock/v1";

/// After this long without a master-password unlock, quick unlock refuses.
pub const QUICK_UNLOCK_MAX_AGE_MS: i64 = 14 * 24 * 60 * 60 * 1000;

impl Vault {
    /// Returns the secret the caller must store behind biometrics. Calling
    /// it again replaces (and invalidates) any previous secret.
    pub fn enable_quick_unlock(&mut self) -> Result<Zeroizing<[u8; KEY_LEN]>> {
        let session = self.session()?;
        let mut secret = Zeroizing::new([0u8; KEY_LEN]);
        OsRng
            .try_fill_bytes(secret.as_mut())
            .map_err(|_| VaultError::Corrupt("random generator failure"))?;
        let mut copy = *secret;
        let key = SymmetricKey::from_bytes(&mut copy);
        let wrapped = hierarchy::wrap_key(&key, &session.account_key, &aad(&session.account_id))?;
        self.store.set_meta(META_QUICK_UNLOCK, &wrapped)?;
        Ok(secret)
    }

    pub fn quick_unlock(&mut self, secret: &[u8]) -> Result<()> {
        let (account_id, _) = self.account()?;
        let wrapped = self
            .store
            .get_meta(META_QUICK_UNLOCK)?
            .ok_or(VaultError::PasswordRequired)?;
        let last = self
            .store
            .get_meta(META_LAST_PASSWORD_UNLOCK)?
            .and_then(|b| b.try_into().ok().map(i64::from_le_bytes))
            .ok_or(VaultError::PasswordRequired)?;
        if now_ms().saturating_sub(last) > QUICK_UNLOCK_MAX_AGE_MS {
            return Err(VaultError::PasswordRequired);
        }

        let mut raw: [u8; KEY_LEN] = secret
            .try_into()
            .map_err(|_| VaultError::WrongCredentials)?;
        let key = SymmetricKey::from_bytes(&mut raw);
        let account_key =
            hierarchy::unwrap_key(&key, &wrapped, &aad(&account_id)).map_err(wrong_credentials)?;
        self.open_session(account_id, account_key)
    }

    pub fn disable_quick_unlock(&mut self) -> Result<()> {
        self.store.delete_meta(META_QUICK_UNLOCK)
    }

    /// Readable while locked, to decide whether to offer biometrics.
    pub fn has_quick_unlock(&self) -> Result<bool> {
        Ok(self.store.get_meta(META_QUICK_UNLOCK)?.is_some())
    }

    pub(crate) fn record_password_unlock(&mut self) -> Result<()> {
        self.store
            .set_meta(META_LAST_PASSWORD_UNLOCK, &now_ms().to_le_bytes())
    }

    #[cfg(test)]
    pub(crate) fn backdate_password_unlock(&mut self, ms: i64) -> Result<()> {
        let last = now_ms() - ms;
        self.store
            .set_meta(META_LAST_PASSWORD_UNLOCK, &last.to_le_bytes())
    }
}

fn aad(account_id: &str) -> Aad {
    Aad::new(QUICK_UNLOCK_LABEL).field(account_id.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ItemData, KdfParams, SecretKey};

    const PW: &[u8] = b"correct horse battery staple";

    fn vault() -> (Vault, SecretKey) {
        let mut v = Vault::open_in_memory().unwrap();
        let sk = v.create(PW, KdfParams::DEFAULT).unwrap();
        let mut d = ItemData::default();
        d.title = "x".into();
        v.add_item(&d).unwrap();
        (v, sk)
    }

    #[test]
    fn enable_lock_and_quick_unlock() {
        let (mut v, _) = vault();
        assert!(!v.has_quick_unlock().unwrap());
        let secret = v.enable_quick_unlock().unwrap();
        v.lock();
        assert!(v.has_quick_unlock().unwrap());
        v.quick_unlock(secret.as_ref()).unwrap();
        assert_eq!(v.items().unwrap().len(), 1);
    }

    #[test]
    fn wrong_or_old_secret_fails() {
        let (mut v, _) = vault();
        let old = v.enable_quick_unlock().unwrap();
        let new = v.enable_quick_unlock().unwrap();
        v.lock();
        assert!(matches!(
            v.quick_unlock(old.as_ref()),
            Err(VaultError::WrongCredentials)
        ));
        assert!(matches!(
            v.quick_unlock(&[1, 2, 3]),
            Err(VaultError::WrongCredentials)
        ));
        v.quick_unlock(new.as_ref()).unwrap();
    }

    #[test]
    fn requires_password_periodically() {
        let (mut v, sk) = vault();
        let secret = v.enable_quick_unlock().unwrap();
        v.backdate_password_unlock(QUICK_UNLOCK_MAX_AGE_MS + 1)
            .unwrap();
        v.lock();
        assert!(matches!(
            v.quick_unlock(secret.as_ref()),
            Err(VaultError::PasswordRequired)
        ));
        v.unlock(PW, &sk).unwrap();
        v.lock();
        v.quick_unlock(secret.as_ref()).unwrap();
    }

    #[test]
    fn password_change_disables_it() {
        let (mut v, sk) = vault();
        let secret = v.enable_quick_unlock().unwrap();
        v.change_password(PW, b"new password", &sk, KdfParams::DEFAULT)
            .unwrap();
        assert!(!v.has_quick_unlock().unwrap());
        v.lock();
        assert!(matches!(
            v.quick_unlock(secret.as_ref()),
            Err(VaultError::PasswordRequired)
        ));
    }

    #[test]
    fn disabled_means_password_required() {
        let (mut v, _) = vault();
        let secret = v.enable_quick_unlock().unwrap();
        v.disable_quick_unlock().unwrap();
        v.lock();
        assert!(matches!(
            v.quick_unlock(secret.as_ref()),
            Err(VaultError::PasswordRequired)
        ));
    }
}
