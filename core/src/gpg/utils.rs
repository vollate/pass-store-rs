use std::error::Error;
use std::io::Read;
use std::process::{Child, Command};

use regex::Regex;

use crate::gpg::GPGClient;

pub(crate) fn user_email_to_fingerprint(
    executable: &str,
    email: &str,
) -> Result<String, Box<dyn Error>> {
    let output =
        Command::new(executable).args(&["--list-keys", "--with-colons", email]).output()?;
    if !output.status.success() {
        return Err("Failed to get GPG key".into());
    }
    let info = String::from_utf8(output.stdout)?;
    for line in info.lines() {
        if line.starts_with("fpr") {
            if let Some(fingerprint) = line.split(':').nth(9) {
                return Ok(fingerprint.to_string());
            }
        }
    }
    Err("No GPG key found".into())
}

pub(crate) fn fingerprint_to_email(
    executable: &str,
    fingerprint: &str,
) -> Result<String, Box<dyn Error>> {
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

#[derive(Eq, PartialEq)]
pub(crate) enum RecipientType {
    Fingerprint,
    UserEmail,
}

pub(crate) fn check_recipient_type(recipient: &str) -> Result<RecipientType, Box<dyn Error>> {
    let fpr_regex = Regex::new(r"^[A-Fa-f0-9]{40}$")?;
    if fpr_regex.is_match(recipient) {
        Ok(RecipientType::Fingerprint)
    } else {
        Ok(RecipientType::UserEmail)
    }
}

pub(crate) fn recipient_to_fingerprint(recipient: &str) -> Result<String, Box<dyn Error>> {
    match check_recipient_type(recipient)? {
        RecipientType::Fingerprint => Ok(recipient.to_string()),
        RecipientType::UserEmail => Ok(recipient.to_string()),
    }
}

pub(super) fn wait_child_process(cmd: &mut Child) -> Result<(), Box<dyn Error>> {
    let status = cmd.wait()?;
    if status.success() {
        Ok(())
    } else {
        let err_msg = match cmd.stderr.take() {
            Some(mut stderr) => {
                let mut buf = String::new();
                stderr.read_to_string(&mut buf)?;
                buf
            }
            None => return Err("Failed to read stderr".into()),
        };
        Err(format!("Failed to edit GPG key, code: {:?}\nError: {}", status, err_msg).into())
    }
}

impl GPGClient {
    pub(crate) fn new(
        executable: String,
        key_fpr: Option<String>,
        username: Option<String>,
        email: Option<String>,
    ) -> Self {
        let mut gpg_client = GPGClient { executable, key_fpr, username, email };
        let _ = gpg_client.update_info();
        gpg_client
    }

    pub(crate) fn get_executable(&self) -> &str {
        &self.executable
    }

    pub(crate) fn get_key_fpr(&self) -> Option<&str> {
        self.key_fpr.as_deref()
    }

    pub(crate) fn get_username(&self) -> Option<&str> {
        self.username.as_deref()
    }

    pub(crate) fn get_email(&self) -> Option<&str> {
        self.email.as_deref()
    }

    pub(crate) fn set_email(&mut self, email: String) -> Result<(), Box<dyn Error>> {
        self.email = Some(email);
        if let Err(e) = self.update_info() {
            self.username = None;
            return Err(e);
        }
        Ok(())
    }

    pub(crate) fn set_username(&mut self, username: String) -> Result<(), Box<dyn Error>> {
        self.username = Some(username);
        if let Err(e) = self.update_info() {
            self.username = None;
            return Err(e);
        }
        Ok(())
    }

    pub(super) fn update_info(&mut self) -> Result<(), Box<dyn Error>> {
        //TODO: update username
        match (&self.key_fpr, &self.username, &self.email) {
            (Some(_), Some(_), Some(_)) => {}
            (Some(k), _, _) => {
                self.email = Some(fingerprint_to_email(&self.executable, k)?);
            }
            (_, Some(u), Some(m)) => {
                self.key_fpr = Some(user_email_to_fingerprint(&self.executable, m)?);
            }
            (None, None, None) => {
                return Err("Either key_fpr or email need to be set".into());
            }
            _ => {}
        }
        Ok(())
    }
}

#[cfg(test)]
mod gpg_client_tests {
    use std::process::{Command, Stdio};

    use pretty_assertions::assert_eq;
    use serial_test::serial;

    use super::user_email_to_fingerprint;
    use crate::gpg::GPGClient;
    use crate::util::test_utils::{
        clean_up_test_key, get_test_email, get_test_executable, get_test_username,
        gpg_key_gen_example_batch,
    };

    #[test]
    #[serial]
    fn test_email_to_fingerprints() {
        let mut test_client = GPGClient::new(
            get_test_executable(),
            None,
            Some(get_test_username()),
            Some(get_test_email()),
        );
        test_client.key_gen_batch(&gpg_key_gen_example_batch()).unwrap();
        let fpr = user_email_to_fingerprint(
            test_client.get_executable(),
            test_client.get_email().unwrap(),
        )
        .unwrap();
        let status = Command::new(test_client.get_executable())
            .args(&["--list-keys", "--with-colons", &fpr])
            .stdout(Stdio::null())
            .status()
            .unwrap();
        assert_eq!(true, status.success());
        clean_up_test_key(test_client.get_executable(), test_client.get_email().unwrap()).unwrap();
    }
}
