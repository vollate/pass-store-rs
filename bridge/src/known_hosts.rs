use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use hmac::{Hmac, Mac};
use sha1::Sha1;

type HmacSha1 = Hmac<Sha1>;

/// Returns the SSH host and port for an SSH URL. Other URLs return `None`.
pub fn ssh_remote_endpoint(url: &str) -> Option<(String, u16)> {
    let value = url.trim();
    if let Some(rest) = value.strip_prefix("ssh://") {
        let host_path = rest.split_once('@').map(|(_, host)| host).unwrap_or(rest);
        let host_port = host_path.split('/').next().unwrap_or("");
        return split_host_port(host_port);
    }
    if value.contains("://") {
        return None;
    }
    let (user_host, _) = value.split_once(':')?;
    if !user_host.contains('@') {
        return None;
    }
    let host = user_host.rsplit_once('@')?.1;
    if host.is_empty() {
        return None;
    }
    Some((host.to_string(), 22))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RemoteHostKeyTrust {
    Trusted,
    Unknown,
    Changed,
}

/// True when [key] for [hostname]:[port] is listed in OpenSSH `known_hosts` text
/// and is not revoked.
pub fn remote_host_key_is_trusted(
    known_hosts: &str,
    hostname: &str,
    port: u16,
    key_type: &str,
    key: &[u8],
) -> bool {
    remote_host_key_trust(known_hosts, hostname, port, key_type, key) == RemoteHostKeyTrust::Trusted
}

/// Whether the presented host key matches stored lines for that host.
///
/// `Unknown` means this host has no stored key yet. `Changed` means a stored
/// line for the host does not match, including a revoked key.
pub fn remote_host_key_trust(
    known_hosts: &str,
    hostname: &str,
    port: u16,
    key_type: &str,
    key: &[u8],
) -> RemoteHostKeyTrust {
    let candidates = host_candidates(hostname, port);
    let mut saw_host = false;
    let mut trusted = false;
    for line in known_hosts.lines() {
        let Some(entry) = parse_known_host_line(line) else {
            continue;
        };
        if !host_list_matches(&entry.hosts, &candidates) {
            continue;
        }
        saw_host = true;
        if entry.revoked && entry.key_type == key_type && entry.key.as_slice() == key {
            return RemoteHostKeyTrust::Changed;
        }
        if entry.cert_authority {
            continue;
        }
        if entry.key_type == key_type && entry.key.as_slice() == key {
            trusted = true;
        }
    }
    if trusted {
        RemoteHostKeyTrust::Trusted
    } else if saw_host {
        RemoteHostKeyTrust::Changed
    } else {
        RemoteHostKeyTrust::Unknown
    }
}

pub fn format_known_host_line(hostname: &str, port: u16, key_type: &str, key: &[u8]) -> String {
    let host = hostname.trim().trim_matches(|c| c == '[' || c == ']');
    let name = if port == 22 { host.to_string() } else { format!("[{host}]:{port}") };
    format!("{name} {key_type} {}\n", STANDARD.encode(key))
}

struct KnownHostEntry {
    hosts: String,
    key_type: String,
    key: Vec<u8>,
    revoked: bool,
    cert_authority: bool,
}

fn parse_known_host_line(line: &str) -> Option<KnownHostEntry> {
    let trimmed = line.trim();
    if trimmed.is_empty() || trimmed.starts_with('#') {
        return None;
    }
    let mut parts = trimmed.split_whitespace();
    let first = parts.next()?;
    let (marker, hosts) = if let Some(marker) = first.strip_prefix('@') {
        (Some(marker), parts.next()?.to_string())
    } else {
        (None, first.to_string())
    };
    let key_type = parts.next()?.to_string();
    let key = decode_known_host_key(parts.next()?)?;
    Some(KnownHostEntry {
        hosts,
        key_type,
        key,
        revoked: marker == Some("revoked"),
        cert_authority: marker == Some("cert-authority"),
    })
}

fn decode_known_host_key(token: &str) -> Option<Vec<u8>> {
    STANDARD
        .decode(token)
        .ok()
        .or_else(|| base64::engine::general_purpose::STANDARD_NO_PAD.decode(token).ok())
}

fn host_candidates(hostname: &str, port: u16) -> Vec<String> {
    let host = hostname.trim().trim_matches(|c| c == '[' || c == ']');
    if port == 22 {
        vec![host.to_string(), format!("[{host}]:22")]
    } else {
        vec![format!("[{host}]:{port}")]
    }
}

fn host_list_matches(list: &str, candidates: &[String]) -> bool {
    let mut matched = false;
    for pattern in list.split(',') {
        let pattern = pattern.trim();
        if pattern.is_empty() {
            continue;
        }
        let (negated, pattern) = match pattern.strip_prefix('!') {
            Some(rest) => (true, rest),
            None => (false, pattern),
        };
        let hit = candidates.iter().any(|candidate| host_pattern_matches(pattern, candidate));
        if hit && negated {
            return false;
        }
        if hit {
            matched = true;
        }
    }
    matched
}

fn host_pattern_matches(pattern: &str, candidate: &str) -> bool {
    if let Some(rest) = pattern.strip_prefix("|1|") {
        return hashed_host_matches(rest, candidate);
    }
    glob_match(pattern.as_bytes(), candidate.as_bytes())
}

fn hashed_host_matches(salt_and_hash: &str, candidate: &str) -> bool {
    let Some((salt_b64, hash_b64)) = salt_and_hash.split_once('|') else {
        return false;
    };
    let Some(salt) = decode_known_host_key(salt_b64) else {
        return false;
    };
    let Some(expected) = decode_known_host_key(hash_b64) else {
        return false;
    };
    hmac_sha1(&salt, candidate.as_bytes()).as_deref() == Some(expected.as_slice())
}

fn hmac_sha1(key: &[u8], data: &[u8]) -> Option<Vec<u8>> {
    let mut mac = HmacSha1::new_from_slice(key).ok()?;
    mac.update(data);
    Some(mac.finalize().into_bytes().to_vec())
}

fn glob_match(pattern: &[u8], text: &[u8]) -> bool {
    let mut pattern_index = 0;
    let mut text_index = 0;
    let mut star_pattern = None;
    let mut star_text = 0;
    while text_index < text.len() {
        if pattern_index < pattern.len()
            && (pattern[pattern_index] == b'?' || pattern[pattern_index] == text[text_index])
        {
            pattern_index += 1;
            text_index += 1;
        } else if pattern_index < pattern.len() && pattern[pattern_index] == b'*' {
            star_pattern = Some(pattern_index);
            star_text = text_index;
            pattern_index += 1;
        } else if let Some(star) = star_pattern {
            pattern_index = star + 1;
            star_text += 1;
            text_index = star_text;
        } else {
            return false;
        }
    }
    while pattern_index < pattern.len() && pattern[pattern_index] == b'*' {
        pattern_index += 1;
    }
    pattern_index == pattern.len()
}

fn split_host_port(host_port: &str) -> Option<(String, u16)> {
    if host_port.is_empty() {
        return None;
    }
    if let Some(rest) = host_port.strip_prefix('[') {
        let (host, after) = rest.split_once(']')?;
        if host.is_empty() {
            return None;
        }
        if after.is_empty() {
            return Some((host.to_string(), 22));
        }
        let port = after.strip_prefix(':')?.parse().ok()?;
        return Some((host.to_string(), port));
    }
    if let Some((host, port)) = host_port.rsplit_once(':') {
        if !host.is_empty() && !port.is_empty() && port.bytes().all(|byte| byte.is_ascii_digit()) {
            return Some((host.to_string(), port.parse().ok()?));
        }
    }
    Some((host_port.to_string(), 22))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hmac_sha1_matches_rfc_2202_case_2() {
        let digest = hmac_sha1(b"Jefe", b"what do ya want for nothing?").expect("hmac");
        assert_eq!(hex_encode(&digest), "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79");
    }

    #[test]
    fn plain_known_host_accepts_only_the_listed_key() {
        let known_hosts = "github.com ssh-ed25519 AAA=\n# comment\n";
        let key = STANDARD.decode("AAA=").unwrap();
        assert!(remote_host_key_is_trusted(known_hosts, "github.com", 22, "ssh-ed25519", &key));
        assert!(!remote_host_key_is_trusted(known_hosts, "gitlab.com", 22, "ssh-ed25519", &key));
        assert!(!remote_host_key_is_trusted(known_hosts, "github.com", 2222, "ssh-ed25519", &key));
    }

    #[test]
    fn bracketed_port_and_revocation_are_honored() {
        let key = STANDARD.decode("AAA=").unwrap();
        let known_hosts = "[git.example.com]:2222 ssh-ed25519 AAA=\n\
            @revoked github.com ssh-ed25519 AAA=\n\
            github.com ssh-ed25519 AAA=\n";
        assert!(remote_host_key_is_trusted(
            known_hosts,
            "git.example.com",
            2222,
            "ssh-ed25519",
            &key
        ));
        assert!(!remote_host_key_is_trusted(known_hosts, "github.com", 22, "ssh-ed25519", &key));
    }

    #[test]
    fn hashed_known_host_matches_the_hashed_name() {
        let salt = b"salt-for-known-host";
        let digest = hmac_sha1(salt, b"github.com").unwrap();
        let known_hosts =
            format!("|1|{}|{} ssh-ed25519 AAA=\n", STANDARD.encode(salt), STANDARD.encode(digest));
        let key = STANDARD.decode("AAA=").unwrap();
        assert!(remote_host_key_is_trusted(&known_hosts, "github.com", 22, "ssh-ed25519", &key));
        assert!(!remote_host_key_is_trusted(&known_hosts, "gitlab.com", 22, "ssh-ed25519", &key));
    }

    #[test]
    fn unknown_host_is_distinct_from_a_changed_key() {
        let known_hosts = "github.com ssh-ed25519 AAAA\n";
        let key = STANDARD.decode("AAAA").unwrap();
        let other = STANDARD.decode("AAA=").unwrap();
        assert_eq!(
            remote_host_key_trust(known_hosts, "gitlab.com", 22, "ssh-ed25519", &key),
            RemoteHostKeyTrust::Unknown
        );
        assert_eq!(
            remote_host_key_trust(known_hosts, "github.com", 22, "ssh-ed25519", &other),
            RemoteHostKeyTrust::Changed
        );
    }

    #[test]
    fn ssh_urls_keep_host_and_port() {
        assert_eq!(
            ssh_remote_endpoint("git@github.com:org/repo.git"),
            Some(("github.com".to_string(), 22))
        );
        assert_eq!(
            ssh_remote_endpoint("ssh://git@github.com:2222/org/repo.git"),
            Some(("github.com".to_string(), 2222))
        );
        assert_eq!(ssh_remote_endpoint("https://example.com/pass.git"), None);
    }

    fn hex_encode(bytes: &[u8]) -> String {
        const HEX: &[u8; 16] = b"0123456789abcdef";
        let mut out = String::with_capacity(bytes.len() * 2);
        for byte in bytes {
            out.push(HEX[(byte >> 4) as usize] as char);
            out.push(HEX[(byte & 0x0f) as usize] as char);
        }
        out
    }
}
