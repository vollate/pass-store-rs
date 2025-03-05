pub(crate) mod sub_command;

use anyhow::{Error, Result};
use clap::Parser;
use pars_core::config::ParsConfig;
use sub_command::SubCommands;

use crate::command;
use crate::util::{to_relative_path, to_relative_path_opt};

#[derive(Parser)]
#[command(
    name = "pars",
    about = "Stores, retrieves, generates, and synchronizes passwords securely",
    version = "0.1.0",
    author = "Vollate <uint44t@gmail.com>"
)]
pub struct CliParser {
    #[command(subcommand)]
    pub command: Option<SubCommands>,

    #[arg(trailing_var_arg = true)]
    pub args: Vec<String>,

    #[arg(short = 'R', long = "repo", global = true)]
    pub base_dir: Option<String>,
}

pub fn handle_cli(config: ParsConfig, cli_args: CliParser) -> Result<(), (i32, Error)> {
    match cli_args.command {
        Some(SubCommands::Init { path, gpg_ids: pgp_id }) => {
            command::init::cmd_init(
                &config,
                cli_args.base_dir.as_deref(),
                path.as_deref(),
                &pgp_id,
            )?;
        }
        Some(SubCommands::Grep { search_string }) => {
            command::grep::cmd_grep(&config, cli_args.base_dir.as_deref(), &search_string)?;
        }
        Some(SubCommands::Find { names }) => {
            command::find::cmd_find(&config, cli_args.base_dir.as_deref(), &names)?;
        }
        Some(SubCommands::Ls { clip, qrcode, pass_name }) => {
            let pass_name = to_relative_path_opt(pass_name);
            command::ls::cmd_ls(
                &config,
                cli_args.base_dir.as_deref(),
                clip,
                qrcode,
                pass_name.as_deref(),
            )?;
        }
        Some(SubCommands::Insert { pass_name, echo, multiline, force }) => {
            let pass_name = to_relative_path(pass_name);
            command::insert::cmd_insert(
                &config,
                cli_args.base_dir.as_deref(),
                &pass_name,
                echo,
                multiline,
                force,
            )?;
        }
        Some(SubCommands::Edit { target_pass }) => {
            let target_pass = to_relative_path(target_pass);
            command::edit::cmd_edit(&config, cli_args.base_dir.as_deref(), &target_pass)?;
        }
        Some(SubCommands::Generate {
            no_symbols,
            clip,
            in_place,
            force,
            pass_name,
            pass_length,
        }) => {
            let pass_name = to_relative_path(pass_name);
            command::generate::cmd_generate(
                &config,
                cli_args.base_dir.as_deref(),
                no_symbols,
                clip,
                in_place,
                force,
                &pass_name,
                pass_length,
            )?;
        }
        Some(SubCommands::Rm { recursive, force, pass_name }) => {
            let pass_name = to_relative_path(pass_name);
            command::rm::cmd_rm(
                &config,
                cli_args.base_dir.as_deref(),
                recursive,
                force,
                &pass_name,
            )?;
        }
        Some(SubCommands::Mv { force, old_path, new_path }) => {
            let old_path = to_relative_path(old_path);
            let new_path = to_relative_path(new_path);
            command::mv::cmd_mv(
                &config,
                cli_args.base_dir.as_deref(),
                force,
                &old_path,
                &new_path,
            )?;
        }
        Some(SubCommands::Cp { force, old_path, new_path }) => {
            let old_path = to_relative_path(old_path);
            let new_path = to_relative_path(new_path);
            command::cp::cmd_cp(
                &config,
                cli_args.base_dir.as_deref(),
                force,
                &old_path,
                &new_path,
            )?;
        }
        Some(SubCommands::Git { args }) => {
            command::git::cmd_git(&config, cli_args.base_dir.as_deref(), &args)?;
        }
        None => {
            command::ls::cmd_ls(&config, cli_args.base_dir.as_deref(), None, None, None)?;
        }
    }
    Ok(())
}
