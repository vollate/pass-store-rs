use std::io::BufReader;

use anyhow::Error;
use log::debug;
use pars_core::clipboard::copy_to_clipboard;
use pars_core::config::cli::ParsConfig;
use pars_core::git::add_and_commit;
use pars_core::git::commit::{CommitType, GitCommit};
use pars_core::operation::generate::{generate_io, IOStreams, PasswdGenerateConfig};
use secrecy::zeroize::Zeroize;
use secrecy::ExposeSecret;

use crate::constants::{ParsExitCode, DEFAULT_PASS_LENGTH, SECRET_EXTENSION};
use crate::util::unwrap_root_path;

pub struct GenerateCommandConfig<'a> {
    pub base_dir: Option<&'a str>,
    pub no_symbols: bool,
    pub clip: bool,
    pub in_place: bool,
    pub force: bool,
    pub pass_name: &'a str,
    pub pass_length: Option<usize>,
}

pub fn cmd_generate(
    config: &ParsConfig,
    cmd_config: GenerateCommandConfig,
) -> Result<(), (i32, Error)> {
    let root = unwrap_root_path(cmd_config.base_dir, config);

    let gen_cfg = PasswdGenerateConfig {
        no_symbols: cmd_config.no_symbols,
        in_place: cmd_config.in_place,
        force: cmd_config.force,
        pass_length: cmd_config.pass_length.unwrap_or(DEFAULT_PASS_LENGTH),
        extension: SECRET_EXTENSION.to_string(),
        pgp_executable: config.executable_config.pgp_executable.clone(),
    };

    let mut stdin = BufReader::new(std::io::stdin());
    let mut stdout = std::io::stdout();
    let mut stderr = std::io::stderr();
    let mut io_streams = IOStreams { in_s: &mut stdin, out_s: &mut stdout, err_s: &mut stderr };

    let mut res = generate_io(&root, cmd_config.pass_name, &gen_cfg, &mut io_streams)
        .map_err(|e| (ParsExitCode::Error.into(), e))?;

    if !cmd_config.clip {
        println!(
            "The generated password for '{}' is:\n{}",
            cmd_config.pass_name,
            res.expose_secret()
        );
        res.zeroize();
    } else if let Err(e) = copy_to_clipboard(res, &config.clip_config.clip_time) {
        eprintln!("Failed to copy to clipboard: {}", e);
    }

    let commit = GitCommit::new(&root, CommitType::Generate(cmd_config.pass_name.to_string()));
    debug!("cmd_generate: commit {}", commit);
    add_and_commit(
        &config.executable_config.git_executable,
        &root,
        commit.get_commit_msg().as_str(),
    )
    .map_err(|e| (ParsExitCode::GitError.into(), e))?;

    Ok(())
}
