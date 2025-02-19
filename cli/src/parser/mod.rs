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

pub fn handle_cli(config: ParsConfig, cli: CliParser) -> Result<(), Box<dyn Error>> {
    match cli.command {
        Some(SubCommands::Init { path, gpg_ids }) => {
            command::init::cmd_init(&config, cli.base_dir, path.as_deref(), &gpg_ids)?;
        }
        Some(SubCommands::Ls { subfolder }) => {
            command::ls::cmd_ls(&config, cli.base_dir, subfolder.as_deref())?;
        }
        Some(SubCommands::Grep { args }) => {
            if let Some(search_string) = args.last() {
                let grep_options = &args[..args.len() - 1];
                command::grep::cmd_grep(&config, cli.base_dir, grep_options, search_string)?;
            } else {
                return Err("Error: grep requires at least a search string.".into());
            }
        }
        Some(SubCommands::Find { names }) => {
            command::find::cmd_find(&config, cli.base_dir, &names)?;
        }
        Some(SubCommands::Show { clip, qrcode, pass_name }) => {
            command::show::cmd_show(&config, cli.base_dir, clip, qrcode, &pass_name)?;
        }
        Some(SubCommands::Insert { pass_name, echo, multiline, force }) => {
            command::insert::cmd_insert(&config, cli.base_dir, &pass_name, echo, multiline, force)?;
        }
        Some(SubCommands::Edit { pass_name }) => {
            command::edit::cmd_edit(&config, cli.base_dir, &pass_name)?;
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
                cli.base_dir,
                no_symbols,
                clip,
                in_place,
                force,
                &pass_name,
                pass_length,
            )?;
        }
        Some(SubCommands::Rm { recursive, force, pass_name }) => {
            command::rm::cmd_rm(&config, cli.base_dir, recursive, force, &pass_name)?;
        }
        Some(SubCommands::Mv { force, old_path, new_path }) => {
            command::mv::cmd_mv(&config, cli.base_dir, force, &old_path, &new_path)?;
        }
        Some(SubCommands::Cp { force, old_path, new_path }) => {
            command::cp::cmd_cp(&config, cli.base_dir, force, &old_path, &new_path)?;
        }
        Some(SubCommands::Git { args }) => {
            command::git::cmd_git(&config, cli.base_dir, &args)?;
        }
        None => {
            command::ls::cmd_ls(&config, cli.base_dir, None)?;
        }
    }
    Ok(())
}
