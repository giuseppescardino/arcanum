//! The client's IP address, for rate limits and audit logs.

use std::net::{IpAddr, Ipv4Addr, SocketAddr};

use axum::extract::{ConnectInfo, FromRequestParts};
use axum::http::request::Parts;
use axum::http::HeaderMap;

use crate::AppState;

/// With `trust_proxy` the address comes from the last `X-Forwarded-For`
/// entry, the one added by our own reverse proxy (Caddy replaces the header
/// sent by untrusted clients). Otherwise it is the TCP peer address.
pub fn client_ip(headers: &HeaderMap, peer: Option<SocketAddr>, trust_proxy: bool) -> IpAddr {
    if trust_proxy {
        let forwarded = headers
            .get_all("x-forwarded-for")
            .iter()
            .filter_map(|v| v.to_str().ok())
            .flat_map(|v| v.split(','))
            .filter_map(|s| s.trim().parse::<IpAddr>().ok())
            .next_back();
        if let Some(ip) = forwarded {
            return ip;
        }
    }
    peer.map_or(IpAddr::V4(Ipv4Addr::UNSPECIFIED), |p| p.ip())
}

/// Extractor form of [`client_ip`].
pub struct ClientIp(pub IpAddr);

impl FromRequestParts<AppState> for ClientIp {
    type Rejection = std::convert::Infallible;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let peer = parts
            .extensions
            .get::<ConnectInfo<SocketAddr>>()
            .map(|c| c.0);
        Ok(Self(client_ip(
            &parts.headers,
            peer,
            state.config.trust_proxy,
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn headers(xff: &[&str]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for v in xff {
            h.append("x-forwarded-for", v.parse().unwrap());
        }
        h
    }

    #[test]
    fn proxy_header_only_when_trusted() {
        let peer: SocketAddr = "10.0.0.5:4000".parse().unwrap();
        let h = headers(&["198.51.100.7, 203.0.113.9"]);
        assert_eq!(
            client_ip(&h, Some(peer), true),
            "203.0.113.9".parse::<IpAddr>().unwrap()
        );
        assert_eq!(client_ip(&h, Some(peer), false), peer.ip());
        assert_eq!(client_ip(&headers(&["junk"]), Some(peer), true), peer.ip());
        assert_eq!(
            client_ip(&HeaderMap::new(), None, false),
            IpAddr::V4(Ipv4Addr::UNSPECIFIED)
        );
    }
}
