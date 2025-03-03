use anyhow::Error;
use pars_core::clipboard::copy_to_clipboard;
use pars_core::config::ParsConfig;
use pars_core::operation::generate::{generate_io, PasswdGenerateConfig};
use pars_core::pgp::PGPClient;
use pars_core::util::fs_util::get_dir_gpg_id_content;
use secrecy::zeroize::Zeroize;
use secrecy::ExposeSecret;

use crate::constants::{ParsExitCode, DEFAULT_PASS_LENGTH};
use crate::util::unwrap_root_path;

pub fn cmd_generate(
    config: &ParsConfig,
    base_dir: Option<&str>,
    no_symbols: bool,
    clip: bool,
    in_place: bool,
    force: bool,
    pass_name: &str,
    pass_length: Option<usize>,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(base_dir, config);
    let target_path = root.join(pass_name);
    let key_fprs =
        get_dir_gpg_id_content(&root, &target_path).map_err(|e| (ParsExitCode::Error.into(), e))?;
    let pgp_client = PGPClient::new(
        config.executable_config.pgp_executable.clone(),
        &key_fprs.iter().map(|s| s.as_str()).collect::<Vec<&str>>(),
    )
    .map_err(|e| (ParsExitCode::PGPError.into(), e))?;
    let gen_cfg = PasswdGenerateConfig {
        no_symbols,
        in_place,
        force,
        pass_length: pass_length.unwrap_or(DEFAULT_PASS_LENGTH),
    };
    let mut stdin = std::io::stdin().lock();
    let mut stdout = std::io::stdout().lock();
    let mut stderr = std::io::stderr().lock();

    let mut res =
        generate_io(&pgp_client, &root, pass_name, &gen_cfg, &mut stdin, &mut stdout, &mut stderr)
            .map_err(|e| (ParsExitCode::Error.into(), e))?;
    if !clip {
        println!("The generated password for {} is:\n{}", pass_name, res.expose_secret());
        res.zeroize();
    } else {
        copy_to_clipboard(res, Some(45)).map_err(|e| (ParsExitCode::ClipboardError.into(), e))?;
    }
    eprintln!("Handle clip!!!");
    Ok(())
}
