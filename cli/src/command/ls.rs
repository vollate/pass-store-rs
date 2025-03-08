use anyhow::{anyhow, Error, Result};
use fast_qr::{self, QRBuilder};
use log::debug;
use pars_core::clipboard::{copy_to_clipboard, get_clip_time};
use pars_core::config::ParsConfig;
use pars_core::operation::ls_or_show::{ls_io, LsOrShow};
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::get_dir_gpg_id_content;
use pars_core::util::tree::{FilterType, TreeConfig};
use secrecy::zeroize::Zeroize;
use secrecy::{ExposeSecret, SecretString};

use crate::constants::ParsExitCode;
use crate::util::unwrap_root_path;

pub fn cmd_ls(
    config: &ParsConfig,
    base_dir: Option<&str>,
    clip: Option<usize>,
    qrcode: Option<usize>,
    target: Option<&str>,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let target_path = root.join(target.unwrap_or_default());
    debug!("cmd_ls: root {:?}, target_path {:?}", root, target_path);
    let tree_cfg = TreeConfig {
        root: &root,
        target: target.unwrap_or_default(),
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };
    let key_fprs = get_dir_gpg_id_content(&root, &target_path)
        .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let pgp_client = PGPClient::new(
        config.executable_config.pgp_executable.clone(),
        &key_fprs.iter().map(|s| s.as_str()).collect(),
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;

    let res = ls_io(&pgp_client, &tree_cfg, &config.print_config.clone().into())
        .map_err(|e| (ParsExitCode::Error.into(), e))?;
    match res {
        LsOrShow::DirTree(tree) => {
            println!("{}", tree);
            Ok(())
        }
        LsOrShow::Password(mut passwd) => {
            if clip.is_none() && qrcode.is_none() {
                println!("{}", passwd.expose_secret());
                passwd.zeroize();
                return Ok(());
            }

            handle_clip(clip, &passwd)?;

            handle_qr_code(qrcode, passwd)?;

            Ok(())
        }
    }
}

fn handle_qr_code(
    qrcode: Option<usize>,
    passwd: secrecy::SecretBox<str>,
) -> Result<(), (i32, Error)> {
    Ok(if let Some(line_num) = qrcode {
        if let Some(line_content) = passwd.expose_secret().split('\n').nth(line_num - 1) {
            let mut qr_code =
                to_qr_code(line_content.into()).map_err(|e| (ParsExitCode::Error.into(), e))?;
            println!("{}", qr_code.expose_secret());
            qr_code.zeroize();
        } else {
            return Err((
                ParsExitCode::Error.into(),
                anyhow!(format!("There is no password to show at line {}.", line_num)),
            ));
        }
    })
}

fn handle_clip(clip: Option<usize>, passwd: &secrecy::SecretBox<str>) -> Result<(), (i32, Error)> {
    Ok(if let Some(line_num) = clip {
        if let Some(line_content) = passwd.expose_secret().split('\n').nth(line_num - 1) {
            copy_to_clipboard(line_content.into(), get_clip_time())
                .map_err(|e| (ParsExitCode::Error.into(), e))?;
        } else {
            return Err((
                ParsExitCode::Error.into(),
                anyhow!(format!(
                    "There is no password to put on the clipboard at line {}.",
                    line_num
                )),
            ));
        }
    })
}

fn to_qr_code(secret: SecretString) -> anyhow::Result<SecretString> {
    let qr = QRBuilder::new(secret.expose_secret()).build()?;
    Ok(qr.to_str().into())
}
