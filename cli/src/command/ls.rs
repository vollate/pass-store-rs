use anyhow::{anyhow, Error, Result};
use fast_qr::{self, QRBuilder};
use log::debug;
use pars_core::clipboard::copy_to_clipboard;
use pars_core::config::cli::ParsConfig;
use pars_core::operation::ls_or_show::{ls_io, LsOrShow};
use pars_core::util::tree::{FilterType, TreeConfig, TreePrintConfig};
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
    debug!("cmd_ls: root {root:?}, target_path {target_path:?}");

    let tree_cfg = TreeConfig {
        root: &root,
        target: target.unwrap_or_default(),
        filter_type: FilterType::Disable,
        filters: Vec::new(),
    };

    // Pass the pgp_executable to ls_io instead of a PGPClient instance
    let res = ls_io(
        &config.executable_config.pgp_executable,
        &tree_cfg,
        &Into::<TreePrintConfig>::into(&config.print_config),
    )
    .map_err(|e| (ParsExitCode::Error.into(), e))?;

    match res {
        LsOrShow::DirTree(tree) => {
            println!("{tree}");
            Ok(())
        }
        LsOrShow::Password(mut passwd) => {
            if clip.is_none() && qrcode.is_none() {
                println!("{}", passwd.expose_secret());
                passwd.zeroize();
                return Ok(());
            }

            handle_clip(clip, &passwd, config)?;

            handle_qr_code(qrcode, passwd)?;

            Ok(())
        }
    }
}

fn handle_qr_code(
    qrcode: Option<usize>,
    passwd: secrecy::SecretBox<str>,
) -> Result<(), (i32, Error)> {
    if let Some(mut line_num) = qrcode {
        if 0 == line_num {
            line_num = 1;
        }

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
    };
    Ok(())
}

fn handle_clip(
    clip: Option<usize>,
    passwd: &secrecy::SecretBox<str>,
    config: &ParsConfig,
) -> Result<(), (i32, Error)> {
    if let Some(mut line_num) = clip {
        if 0 == line_num {
            line_num = 1;
        }

        if let Some(line_content) = passwd.expose_secret().split('\n').nth(line_num - 1) {
            copy_to_clipboard(line_content.into(), &config.feature_config.clip_time)
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
    };
    Ok(())
}

fn to_qr_code(secret: SecretString) -> Result<SecretString> {
    let qr = QRBuilder::new(secret.expose_secret()).build()?;
    Ok(qr.to_str().into())
}
