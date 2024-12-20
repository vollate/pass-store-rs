use std::error::Error;
use std::process::{Command, Stdio};

use regex::Regex;

use crate::gpg::GPGClient;

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

pub enum RecipientType {
    Fingerprint,
    UserEmail,
}

pub fn check_recipient_type(recipient: &str) -> Result<RecipientType, Box<dyn Error>> {
    let fpr_regex = Regex::new(r"^[A-Fa-f0-9]{40}$")?;
    if fpr_regex.is_match(recipient) {
        Ok(RecipientType::Fingerprint)
    } else {
        Ok(RecipientType::UserEmail)
    }
}

impl GPGClient {
    pub fn user_email_to_fingerprint(
        &self,
        user_email: &str,
    ) -> Result<Vec<String>, Box<dyn Error>> {
        let output = Command::new(&self.executable)
            .args(&["--list-keys", "--with-colons", "--with-fingerprint", user_email])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()?;
        if !output.status.success() {
            Err(std::str::from_utf8(&output.stderr)?.into())
        } else {
            let info = String::from_utf8(output.stdout)?;
            println!("{}", info);
            Ok(vec![user_email.to_string()])
        }
    }

    pub fn recipient_to_fingerprint(&self, recipient: &str) -> Result<String, Box<dyn Error>> {
        match check_recipient_type(recipient)? {
            RecipientType::Fingerprint => Ok(recipient.to_string()),
            RecipientType::UserEmail => Ok(recipient.to_string()),
        }
    }
}

#[cfg(test)]
mod gpg_client_tests {
    use pretty_assertions::{assert_eq, assert_ne};
    use serial_test::serial;

    use crate::gpg::GPGClient;
    use crate::util::test_utils::{
        get_test_email, get_test_executable, get_test_username, gpg_key_gen_example_batch,
    };

    #[test]
    #[serial]
    fn test_email_to_fingerprints() {
        let mut client = GPGClient::new(
            get_test_executable(),
            None,
            Some(get_test_username()),
            Some(get_test_email()),
        );
        client.gpg_key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
    }
}
