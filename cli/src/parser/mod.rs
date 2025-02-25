pub(crate) mod sub_command;

use std::error::Error;

use clap::{CommandFactory, Parser};
use pars_core::config::ParsConfig;
use sub_command::SubCommands;

use crate::command;

#[derive(Parser)]
#[command(
    name = "pars",
    about = "Stores, retrieves, generates, and synchronizes passwords securely",
    version = "1.0",
    author = "Vollate <uint44t@gmail.com>"
)]

pub struct CliParser {
    #[command(subcommand)]
    pub command: Option<SubCommands>,

    #[arg(trailing_var_arg = true)]
    pub args: Vec<String>,

    #[arg(short = 'r', long = "repo", global = true)]
    pub base_dir: Option<String>,
}

pub fn handle_cli(config: ParsConfig, cli_args: CliParser) -> Result<(), (i32, Box<dyn Error>)> {
    match cli_args.command {
        Some(SubCommands::Init { path, gpg_ids: pgp_id }) => {
            command::init::cmd_init(
                &config,
                cli_args.base_dir.as_deref(),
                path.as_deref(),
                &pgp_id,
            )?;
        }
        Some(SubCommands::Ls { subfolder }) => {
            command::ls::cmd_ls(&config, cli_args.base_dir.as_deref(), subfolder.as_deref())?;
        }
        Some(SubCommands::Grep { args }) => {
            if let Some(search_string) = args.last() {
                let grep_options = &args[..args.len() - 1];
                command::grep::cmd_grep(
                    &config,
                    cli_args.base_dir.as_deref(),
                    grep_options,
                    search_string,
                )?;
            } else {
                return Err((0, "Error: grep requires at least a search string.".into()));
            }
        }
        Some(SubCommands::Find { names }) => {
            command::find::cmd_find(&config, cli_args.base_dir.as_deref(), &names)?;
        }
        Some(SubCommands::Show { clip, qrcode, pass_name }) => {
            command::show::cmd_show(
                &config,
                cli_args.base_dir.as_deref(),
                clip,
                qrcode,
                &pass_name,
            )?;
        }
        Some(SubCommands::Insert { pass_name, echo, multiline, force }) => {
            command::insert::cmd_insert(
                &config,
                cli_args.base_dir.as_deref(),
                &pass_name,
                echo,
                multiline,
                force,
            )?;
        }
        Some(SubCommands::Edit { pass_name }) => {
            command::edit::cmd_edit(&config, cli_args.base_dir.as_deref(), &pass_name)?;
        }
        Some(SubCommands::Generate {
            no_symbols,
            clip,
            in_place,
            force,
            pass_name,
            pass_length,
        }) => {
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
            command::rm::cmd_rm(
                &config,
                cli_args.base_dir.as_deref(),
                recursive,
                force,
                &pass_name,
            )?;
        }
        Some(SubCommands::Mv { force, old_path, new_path }) => {
            command::mv::cmd_mv(
                &config,
                cli_args.base_dir.as_deref(),
                force,
                &old_path,
                &new_path,
            )?;
        }
        Some(SubCommands::Cp { force, old_path, new_path }) => {
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
            command::ls::cmd_ls(&config, cli_args.base_dir.as_deref(), None)?;
        }
    }
    Ok(())
}
