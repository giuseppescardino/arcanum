//! Network half of the breached-password check against Have I Been Pwned
//! "Pwned Passwords". Only the five-digit SHA-1 prefix leaves the device,
//! over HTTPS and with `Add-Padding`, so the response size doesn't reveal
//! the range either. Matching happens in [`arcanum_tools::breach`].

use std::sync::OnceLock;
use std::time::Duration;

use arcanum_tools::breach::{count_in_range, range_query};

use crate::{Result, SyncError};

const RANGE_URL: &str = "https://api.pwnedpasswords.com/range/";

/// Times `password` appears in known breaches; 0 if it was never seen.
pub fn pwned_count(password: &str) -> Result<u64> {
    pwned_count_at(RANGE_URL, password)
}

fn pwned_count_at(range_url: &str, password: &str) -> Result<u64> {
    let query = range_query(password);
    let response = agent()
        .get(&format!("{range_url}{}", query.prefix))
        .set("Add-Padding", "true")
        .call();
    let body = match response {
        Ok(resp) => resp
            .into_string()
            .map_err(|e| SyncError::Network(e.to_string()))?,
        Err(ureq::Error::Status(429, _)) => return Err(SyncError::TooManyRequests),
        Err(ureq::Error::Status(status, _)) => {
            return Err(SyncError::Server(format!("HTTP {status}")))
        }
        Err(ureq::Error::Transport(t)) => return Err(SyncError::Network(t.to_string())),
    };
    Ok(count_in_range(&body, &query.suffix))
}

/// Shared so a vault-wide check reuses the TLS connection.
fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            // HIBP requires a user agent that names the client.
            .user_agent(concat!(
                "Arcanum-password-manager/",
                env!("CARGO_PKG_VERSION")
            ))
            .build()
    })
}

#[cfg(test)]
mod tests {
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpListener;
    use std::thread;

    use super::*;

    /// One-shot HTTP server: returns the request head it received.
    fn serve(status: &'static str, body: &'static str) -> (String, thread::JoinHandle<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap_or_else(|e| panic!("{e}"));
        let url = format!(
            "http://{}/range/",
            listener.local_addr().unwrap_or_else(|e| panic!("{e}"))
        );
        let handle = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap_or_else(|e| panic!("{e}"));
            let mut head = String::new();
            let mut reader = BufReader::new(stream.try_clone().unwrap_or_else(|e| panic!("{e}")));
            loop {
                let mut line = String::new();
                if reader.read_line(&mut line).unwrap_or(0) == 0 || line == "\r\n" {
                    break;
                }
                head.push_str(&line);
            }
            let _ = write!(
                stream,
                "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            head
        });
        (url, handle)
    }

    #[test]
    fn sends_only_the_prefix_with_padding() {
        let (url, server) = serve(
            "200 OK",
            "1E4C9B93F3F0682250B6CF8331B7EE68FD8:42\r\nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:0\r\n",
        );
        assert_eq!(pwned_count_at(&url, "password").ok(), Some(42));
        let head = server.join().unwrap_or_default().to_ascii_lowercase();
        assert!(head.starts_with("get /range/5baa6 http/1.1"), "{head}");
        assert!(head.contains("add-padding: true"), "{head}");
        assert!(
            head.contains("user-agent: arcanum-password-manager/"),
            "{head}"
        );
        assert!(!head.contains("1e4c9b93"), "suffix leaked: {head}");
    }

    #[test]
    fn unknown_password_counts_zero() {
        let (url, server) = serve("200 OK", "0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n");
        assert_eq!(pwned_count_at(&url, "password").ok(), Some(0));
        let _ = server.join();
    }

    #[test]
    fn errors_are_not_reported_as_safe() {
        let (url, server) = serve("429 Too Many Requests", "");
        assert!(matches!(
            pwned_count_at(&url, "password"),
            Err(SyncError::TooManyRequests)
        ));
        let _ = server.join();

        let (url, server) = serve("503 Service Unavailable", "");
        assert!(matches!(
            pwned_count_at(&url, "password"),
            Err(SyncError::Server(_))
        ));
        let _ = server.join();
    }
}
