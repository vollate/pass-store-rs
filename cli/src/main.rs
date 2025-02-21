mod command;
mod constants;
mod parser;
mod util;

use std::env;

use clap::Parser;
use constants::ParsExitCode;
use pars_core::config::loader::load_config;
use parser::CliParser;

use crate::constants::default_config_path;

fn main() {
    let config_path = env::var("PASS_CONFIG_PATH").unwrap_or(default_config_path());
    process_cli(&config_path);
}

fn process_cli(config_path: &str) {
    let config = match load_config(config_path) {
        Ok(config) => config,
        Err(e) => {
            eprintln!("Failed to load config file: {}", e);
            std::process::exit(ParsExitCode::Error as i32);
        }
    };

    let cli_args = CliParser::parse();

    match parser::handle_cli(config, cli_args) {
        Ok(_) => {}
        Err((code, e)) => {
            eprintln!("Error: {}", e);
            std::process::exit(code);
        }
    }
}
