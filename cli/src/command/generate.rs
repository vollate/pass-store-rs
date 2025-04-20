use std::io::BufReader;

use anyhow::Error;
use log::debug;
use pars_core::clipboard::{copy_to_clipboard, get_clip_time};
use pars_core::config::cli::ParsConfig;
use pars_core::git::add_and_commit;
use pars_core::git::commit::{CommitType, GitCommit};
use pars_core::operation::generate::{generate_io, PasswdGenerateConfig};
use secrecy::zeroize::Zeroize;
use secrecy::ExposeSecret;

use crate::constants::{ParsExitCode, DEFAULT_PASS_LENGTH, SECRET_EXTENSION};
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

    let gen_cfg = PasswdGenerateConfig {
        no_symbols,
        in_place,
        force,
        pass_length: pass_length.unwrap_or(DEFAULT_PASS_LENGTH),
        extension: SECRET_EXTENSION.to_string(),
        pgp_executable: config.executable_config.pgp_executable.clone(),
    };

    let mut res = generate_io(
        &root,
        pass_name,
        &gen_cfg,
        &mut BufReader::new(std::io::stdin()),
        &mut std::io::stdout(),
        &mut std::io::stderr(),
    )
    .map_err(|e| (ParsExitCode::Error.into(), e))?;

    if !clip {
        println!("The generated password for '{}' is:\n{}", pass_name, res.expose_secret());
        res.zeroize();
    } else if let Err(e) = copy_to_clipboard(res, get_clip_time()) {
        eprintln!("Failed to copy to clipboard: {}", e);
    }

    let commit = GitCommit::new(&root, CommitType::Generate(pass_name.to_string()));
    debug!("cmd_generate: commit {}", commit);
    add_and_commit(
        &config.executable_config.git_executable,
        &root,
        commit.get_commit_msg().as_str(),
    )
    .map_err(|e| (ParsExitCode::GitError.into(), e))?;

    Ok(())
}
