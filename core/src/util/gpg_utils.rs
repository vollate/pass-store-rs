use std::error::Error;
use std::process::{Command, Stdio};

pub fn email_to_fingerprints(executable: &str, email: &str) -> Result<Vec<String>, Box<dyn Error>> {
    let output =
        Command::new(executable).args(&["--list-keys", "--with-colons", email]).output()?;
    if !output.status.success() {
        return Err("Failed to get GPG key".into());
    }
    let info = String::from_utf8(output.stdout)?;
    let mut found_target = false;
    let mut fingerprints = Vec::new();
    for line in info.lines() {
        if line.starts_with("uid") && line.contains(email) {
            found_target = true;
        } else if line.starts_with("fpr") && found_target {
            if let Some(fingerprint) = line.split(':').nth(9) {
                fingerprints.push(fingerprint.to_string());
            }
            found_target = false;
        }
    }

    if fingerprints.len() == 0 {
        Err("No GPG key found".into())
    } else {
        Ok(fingerprints)
    }
}

pub fn fingerprint_to_email(executable: &str, fingerprint: &str) -> Result<String, Box<dyn Error>> {
    let output =
        Command::new(executable).args(&["--list-keys", "--with-colons", fingerprint]).output()?;
    if !output.status.success() {
        return Err("Failed to get GPG key".into());
    }
    let info = String::from_utf8(output.stdout)?;
    for line in info.lines() {
        if line.starts_with("uid") {
            let email = line.split('<').nth(1).unwrap().split('>').nth(0).unwrap();
            return Ok(email.to_string());
        }
    }
    Err(format!("No email found for {}", fingerprint).into())
}
