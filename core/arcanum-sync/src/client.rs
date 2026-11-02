use std::time::Duration;

use arcanum_crypto::account::EncryptedAccountKeys;
use arcanum_proto::opaque_ke::{
    ClientLogin, ClientLoginFinishParameters, ClientRegistration,
    ClientRegistrationFinishParameters, CredentialResponse, Identifiers, RegistrationResponse,
};
use arcanum_proto::{
    DeviceInfo, ErrorCode, ErrorResponse, LoginFinishRequest, LoginStartRequest,
    LoginStartResponse, OpaqueMessage, OpaqueSuite, PasswordFinishRequest, PreloginRequest,
    PreloginResponse, PullResponse, PushRequest, PushResponse, RegisterFinishRequest,
    RegisterStartRequest, SessionResponse, VaultRecord, OPAQUE_CONTEXT,
};
use arcanum_vault::{AccountBundle, AuthKey, SyncTransport};
use rand_core::OsRng;
use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::{Result, SyncError};

/// Plain HTTP is allowed only for local development servers.
const LOCAL_HTTP_HOSTS: &[&str] = &["localhost", "127.0.0.1", "[::1]", "10.0.2.2"];

pub struct Client {
    agent: ureq::Agent,
    base: String,
    token: Option<String>,
}

impl Client {
    pub fn new(server_url: &str) -> Result<Self> {
        let base = normalize_url(server_url)?;
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(10))
            .timeout(Duration::from_secs(60))
            .user_agent(concat!("arcanum-sync/", env!("CARGO_PKG_VERSION")))
            .build();
        Ok(Self {
            agent,
            base,
            token: None,
        })
    }

    pub fn with_token(mut self, token: String) -> Self {
        self.token = Some(token);
        self
    }

    pub fn base_url(&self) -> &str {
        &self.base
    }

    pub fn prelogin(&self, email: &str) -> Result<PreloginResponse> {
        self.post(
            "/v1/prelogin",
            &PreloginRequest {
                email: email.to_owned(),
            },
        )
    }

    pub fn register(
        &mut self,
        email: &str,
        auth_key: &AuthKey,
        bundle: &AccountBundle,
        device_name: &str,
    ) -> Result<SessionResponse> {
        let upload = self.opaque_registration("/v1/register/start", Some(email), auth_key)?;
        let session: SessionResponse = self.post(
            "/v1/register/finish",
            &RegisterFinishRequest {
                email: email.to_owned(),
                message: upload,
                account_id: bundle.account_id.clone(),
                account_keys: bundle.keys.clone(),
                vault: VaultRecord {
                    id: bundle.vault_id.clone(),
                    wrapped_key: bundle.wrapped_vault_key.clone(),
                },
                device_name: device_name.to_owned(),
            },
        )?;
        self.token = Some(session.token.clone());
        Ok(session)
    }

    pub fn login(
        &mut self,
        email: &str,
        auth_key: &AuthKey,
        device_name: &str,
    ) -> Result<SessionResponse> {
        let (login_id, message) = self.opaque_login(email, auth_key)?;
        let session: SessionResponse = self.post(
            "/v1/login/finish",
            &LoginFinishRequest {
                login_id,
                message,
                device_name: device_name.to_owned(),
            },
        )?;
        self.token = Some(session.token.clone());
        Ok(session)
    }

    /// Re-registers OPAQUE with the new auth key and uploads the re-wrapped
    /// Account Key, proving the current password with a fresh OPAQUE login
    /// (the session token alone is not enough). Other devices are signed
    /// out by the server.
    pub fn change_password(
        &self,
        email: &str,
        current_auth_key: &AuthKey,
        new_auth_key: &AuthKey,
        keys: &EncryptedAccountKeys,
    ) -> Result<()> {
        let (login_id, login_message) = self.opaque_login(email, current_auth_key)?;
        let upload = self.opaque_registration("/v1/password/start", None, new_auth_key)?;
        self.post_no_content(
            "/v1/password/finish",
            &PasswordFinishRequest {
                login_id,
                login_message,
                message: upload,
                account_keys: keys.clone(),
            },
        )
    }

    /// OPAQUE login up to the client's final message; returns the login id
    /// and the `CredentialFinalization` to send to the server.
    fn opaque_login(&self, email: &str, auth_key: &AuthKey) -> Result<(String, Vec<u8>)> {
        let mut rng = OsRng;
        let start = ClientLogin::<OpaqueSuite>::start(&mut rng, auth_key.as_bytes())
            .map_err(|_| SyncError::Protocol("OPAQUE login start"))?;
        let challenge: LoginStartResponse = self.post(
            "/v1/login/start",
            &LoginStartRequest {
                email: email.to_owned(),
                message: start.message.serialize().to_vec(),
            },
        )?;
        let response = CredentialResponse::<OpaqueSuite>::deserialize(&challenge.message)
            .map_err(|_| SyncError::Protocol("OPAQUE credential response"))?;
        // Fails here (client side) on a wrong password or unknown email.
        let finish = start
            .state
            .finish(
                &mut rng,
                auth_key.as_bytes(),
                response,
                ClientLoginFinishParameters::new(
                    Some(OPAQUE_CONTEXT),
                    Identifiers::default(),
                    None,
                ),
            )
            .map_err(|_| SyncError::InvalidLogin)?;
        Ok((challenge.login_id, finish.message.serialize().to_vec()))
    }
    pub fn logout(&self) -> Result<()> {
        self.post_no_content("/v1/logout", &())
    }

    pub fn devices(&self) -> Result<Vec<DeviceInfo>> {
        self.get("/v1/devices")
    }

    pub fn revoke_device(&self, id: &str) -> Result<()> {
        Self::check(self.request("DELETE", &format!("/v1/devices/{id}")).call()).map(drop)
    }

    /// Both OPAQUE registration round trips; returns the upload message.
    fn opaque_registration(
        &self,
        start_path: &str,
        email: Option<&str>,
        auth_key: &AuthKey,
    ) -> Result<Vec<u8>> {
        let mut rng = OsRng;
        let start = ClientRegistration::<OpaqueSuite>::start(&mut rng, auth_key.as_bytes())
            .map_err(|_| SyncError::Protocol("OPAQUE registration start"))?;
        let message = start.message.serialize().to_vec();
        let reply: OpaqueMessage = match email {
            Some(email) => self.post(
                start_path,
                &RegisterStartRequest {
                    email: email.to_owned(),
                    message,
                },
            )?,
            None => self.post(start_path, &OpaqueMessage { message })?,
        };
        let response = RegistrationResponse::<OpaqueSuite>::deserialize(&reply.message)
            .map_err(|_| SyncError::Protocol("OPAQUE registration response"))?;
        let finish = start
            .state
            .finish(
                &mut rng,
                auth_key.as_bytes(),
                response,
                ClientRegistrationFinishParameters::new(Identifiers::default(), None),
            )
            .map_err(|_| SyncError::Protocol("OPAQUE registration finish"))?;
        Ok(finish.message.serialize().to_vec())
    }

    fn request(&self, method: &str, path: &str) -> ureq::Request {
        let req = self.agent.request(method, &format!("{}{path}", self.base));
        match &self.token {
            Some(t) => req.set("Authorization", &format!("Bearer {t}")),
            None => req,
        }
    }

    fn get<R: DeserializeOwned>(&self, path: &str) -> Result<R> {
        Self::json(Self::check(self.request("GET", path).call())?)
    }

    fn post<B: Serialize, R: DeserializeOwned>(&self, path: &str, body: &B) -> Result<R> {
        Self::json(Self::check(self.request("POST", path).send_json(body))?)
    }

    fn post_no_content<B: Serialize>(&self, path: &str, body: &B) -> Result<()> {
        Self::check(self.request("POST", path).send_json(body)).map(drop)
    }

    fn json<R: DeserializeOwned>(resp: ureq::Response) -> Result<R> {
        resp.into_json()
            .map_err(|_| SyncError::Protocol("invalid JSON"))
    }

    fn check(result: std::result::Result<ureq::Response, ureq::Error>) -> Result<ureq::Response> {
        match result {
            Ok(resp) => Ok(resp),
            Err(ureq::Error::Status(status, resp)) => {
                let body: Option<ErrorResponse> = resp.into_json().ok();
                Err(match body.map(|b| (b.error, b.message)) {
                    Some((ErrorCode::Unauthorized, _)) => SyncError::Unauthorized,
                    Some((ErrorCode::InvalidLogin, _)) => SyncError::InvalidLogin,
                    Some((ErrorCode::EmailTaken, _)) => SyncError::EmailTaken,
                    Some((ErrorCode::TooManyRequests, _)) => SyncError::TooManyRequests,
                    Some((ErrorCode::CursorAhead, _)) => SyncError::ServerRestored,
                    Some((_, message)) => SyncError::Server(message),
                    None => SyncError::Server(format!("HTTP {status}")),
                })
            }
            Err(ureq::Error::Transport(t)) => Err(SyncError::Network(t.to_string())),
        }
    }
}

impl SyncTransport for Client {
    fn pull(&mut self, since: i64) -> arcanum_vault::Result<PullResponse> {
        Ok(self.get(&format!("/v1/sync?since={since}"))?)
    }

    fn push(&mut self, request: &PushRequest) -> arcanum_vault::Result<PushResponse> {
        Ok(self.post("/v1/sync", request)?)
    }
}

/// Parses with a real URL parser (the one ureq uses) so tricks like
/// `http://localhost@evil.com` can't pass as a local address.
fn normalize_url(raw: &str) -> Result<String> {
    let url = url::Url::parse(raw.trim()).map_err(|_| SyncError::InvalidUrl("malformed URL"))?;
    if !url.username().is_empty() || url.password().is_some() {
        return Err(SyncError::InvalidUrl(
            "credentials are not allowed in the URL",
        ));
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err(SyncError::InvalidUrl("unexpected query or fragment"));
    }
    let Some(host) = url.host_str() else {
        return Err(SyncError::InvalidUrl("missing host"));
    };
    match url.scheme() {
        "https" => {}
        "http" if LOCAL_HTTP_HOSTS.contains(&host) => {}
        "http" => return Err(SyncError::InvalidUrl("use https://")),
        _ => return Err(SyncError::InvalidUrl("must start with https://")),
    }
    Ok(url.as_str().trim_end_matches('/').to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_rules() {
        assert_eq!(
            normalize_url(" https://sync.example.com/ ").unwrap(),
            "https://sync.example.com"
        );
        assert_eq!(
            normalize_url("http://localhost:8080").unwrap(),
            "http://localhost:8080"
        );
        assert_eq!(
            normalize_url("http://127.0.0.1:8080/").unwrap(),
            "http://127.0.0.1:8080"
        );
        assert!(normalize_url("http://sync.example.com").is_err());
        assert!(normalize_url("http://localhost.evil.com").is_err());
        // userinfo must not smuggle a remote host past the local allowlist
        assert!(normalize_url("http://localhost:80@evil.com").is_err());
        assert!(normalize_url("http://localhost@evil.com/").is_err());
        assert!(normalize_url("https://user:pw@sync.example.com").is_err());
        assert!(normalize_url("https://sync.example.com/?x=1").is_err());
        assert_eq!(
            normalize_url("https://sync.example.com/pm/").unwrap(),
            "https://sync.example.com/pm"
        );
        assert!(normalize_url("ftp://x").is_err());
        assert!(normalize_url("https://").is_err());
    }
}
