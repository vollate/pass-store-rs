mod command;
mod constants;
mod parser;
mod util;

use std::env;
use std::path::PathBuf;

use clap::Parser;
use constants::{ParsExitCode, DEFAULT_LOG_LEVEL};
use log::LevelFilter;
use pars_core::config::loader::load_config;
use pars_core::config::ParsConfig;
use pars_core::util::log::{init_debug_logger, set_log_level};
use parser::CliParser;

use crate::constants::default_config_path;

fn main() {
    init_debug_logger();
    let log_level: LevelFilter = env::var("PARS_LOG_LEVEL")
        .unwrap_or(DEFAULT_LOG_LEVEL.to_string())
        .parse()
        .unwrap_or(LevelFilter::Info);
    set_log_level(log_level);
    let config_path = env::var("PASS_CONFIG_PATH").unwrap_or(default_config_path());
    process_cli(&config_path);
}

fn process_cli(config_path: &str) {
    let config = if PathBuf::from(&config_path).exists() {
        match load_config(config_path) {
            Ok(config) => config,
            Err(e) => {
                eprintln!("Failed to load config file '{}': {}", config_path, e);
                std::process::exit(ParsExitCode::Error as i32);
            }
        }
    } else {
        ParsConfig::default()
    };

    let cli_args = CliParser::parse();

    if let Err((code, e)) = parser::handle_cli(config, cli_args) {
        eprintln!("{}", e);
        std::process::exit(code);
    }
}
