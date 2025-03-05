use anyhow::{anyhow, Error, Result};
use log::debug;
use pars_core::clipboard::{copy_to_clipboard, get_clip_time};
use pars_core::config::ParsConfig;
use pars_core::operation::ls_or_show::{ls_io, LsOrShow};
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::get_dir_gpg_id_content;
use pars_core::util::tree::{FilterType, TreeConfig};
use secrecy::zeroize::Zeroize;
use secrecy::ExposeSecret;

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

            if let Some(line_num) = clip {
                if line_num == 0 {
                    copy_to_clipboard(passwd.expose_secret().into(), get_clip_time())
                        .map_err(|e| (ParsExitCode::Error.into(), e))?;
                } else if let Some(line_content) =
                    passwd.expose_secret().split('\n').nth(line_num - 1)
                {
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
            }

            if let Some(line_num) = qrcode {
                if line_num == 0 {
                    unimplemented!("QR code generation is not implemented yet.");
                } else if let Some(_line_content) =
                    passwd.expose_secret().split('\n').nth(line_num - 1)
                {
                    unimplemented!("QR code generation is not implemented yet.");
                    // let qr = qrcode::QrCode::new(line_content.as_bytes())?;
                    // let image = qr.render::<unicode_canvas::UnicodeCanvas>().dark_color('█').light_color(' ' ).build();
                    // println!("{}", image);
                } else {
                    return Err((
                        ParsExitCode::Error.into(),
                        anyhow!(format!(
                            "There is no password to put on the clipboard at line {}.",
                            line_num
                        )),
                    ));
                }
            }

            Ok(())
        }
    }
}
