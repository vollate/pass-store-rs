use std::io::Read;
use std::process::{Child, Command};

use anyhow::{anyhow, Result};
use log::debug;

use super::PGPKey;
use crate::pgp::PGPClient;

pub(crate) fn get_pgp_key_info(
    executable: &str,
    identifier: &str,
) -> Result<(String, String, String)> {
    let output =
        Command::new(executable).args(["--list-keys", "--with-colons", identifier]).output()?;
    if !output.status.success() {
        return Err(anyhow!("Failed to get PGP key"));
    }

    let info = String::from_utf8(output.stdout)?;
    debug!("fingerprint output: {}", info);

    let username;
    let mut fpr = String::new();
    for line in info.lines() {
        if line.starts_with("fpr") {
            if let Some(fingerprint) = line.split(':').nth(9) {
                fpr = fingerprint.to_string();
            } else {
                return Err(anyhow!("Failed to parse fingerprint"));
            }
        } else if line.starts_with("uid") {
            if let Some(before_at) = line.split_once(" <") {
                let name_part = before_at.0;

                if let Some(name) = name_part.rsplit(':').next() {
                    username = name.to_string();
                } else {
                    return Err(anyhow!("Failed to parse username"));
                }
            } else {
                return Err(anyhow!("Failed to parse username"));
            }

            let email = line
                .split('<')
                .nth(1)
                .and_then(|part| part.split('>').next())
                .ok_or(anyhow!("Failed to parse email"))?;
            return Ok((fpr, username, email.to_string()));
        }
    }
    Err(anyhow!(format!("No userinfo found for {}", identifier)))
}

pub(super) fn wait_child_process(cmd: &mut Child) -> Result<()> {
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
            None => return Err(anyhow!("Failed to read stderr")),
        };
        Err(anyhow!(format!("Failed to edit PGP key, code: {:?}\nError: {}", status, err_msg)))
    }
}

macro_rules! get_keys_field {
    ($self:ident, $field:ident) => {{
        let mut res = Vec::with_capacity($self.keys.len());
        for key in &$self.keys {
            res.push(key.$field.as_str());
        }
        res
    }};
}

impl PGPClient {
    pub fn new<S: AsRef<str>>(executable: S, infos: &Vec<&str>) -> Result<Self> {
        let mut gpg_client =
            PGPClient { executable: executable.as_ref().to_string(), keys: Vec::new() };
        gpg_client.update_info(infos)?;
        Ok(gpg_client)
    }

    pub fn get_executable(&self) -> &str {
        &self.executable
    }

    pub fn get_key_fprs(&self) -> Vec<&str> {
        get_keys_field!(self, key_fpr)
    }

    pub fn get_usernames(&self) -> Vec<&str> {
        get_keys_field!(self, username)
    }

    pub fn get_email(&self) -> Vec<&str> {
        get_keys_field!(self, email)
    }

    fn update_info(&mut self, infos: &Vec<&str>) -> Result<()> {
        self.keys = Vec::with_capacity(infos.len());
        for info in infos {
            let (fpr, username, email) = get_pgp_key_info(&self.executable, info)?;
            self.keys.push(PGPKey { key_fpr: fpr, username, email });
            debug!("Add key: {:?}", self.keys.last().unwrap());
        }
        Ok(())
    }
}
