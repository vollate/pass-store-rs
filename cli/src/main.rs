mod command;
mod constants;
mod parser;
mod util;

use std::env;
use std::path::PathBuf;

use clap::Parser;
use constants::{ParsExitCode, DEFAULT_LOG_LEVEL};
use log::debug;
use pars_core::config::cli::{load_config, ParsConfig};
use pars_core::constants::env_variables::{CONFIG_PATH_ENV, LOG_LEVEL_VAR};
use pars_core::util::fs_util::default_config_path;
use pars_core::util::log::{init_logger, set_log_level};
use parser::CliParser;

fn main() {
    init_logger();
    let log_level =
        env::var(LOG_LEVEL_VAR).unwrap_or_default().parse().unwrap_or(DEFAULT_LOG_LEVEL);
    set_log_level(log_level);
    let config_path = env::var(CONFIG_PATH_ENV).unwrap_or(default_config_path());
    process_cli(&config_path);
}

fn fix_args(raw: Vec<String>) -> Vec<String> {
    let mut out = Vec::with_capacity(raw.len());
    let mut iter = raw.into_iter();

    if let Some(prog) = iter.next() {
        out.push(prog);
    }

    while let Some(token) = iter.next() {
        if token == "-c" || token == "-q" {
            if let Some(next) = iter.next() {
                if next.parse::<u32>().is_ok() {
                    out.push(format!("{}={}", token, next));
                    continue;
                } else {
                    out.push(token.clone());
                    out.push(next);
                    continue;
                }
            }
            out.push(token);
        } else {
            out.push(token);
        }
    }

    out
}

fn process_cli(config_path: &str) {
    let config = if PathBuf::from(&config_path).exists() {
        match load_config(config_path) {
            Ok(config) => config,
            Err(e) => {
                eprintln!("Failed to load config file '{}': {}", config_path, e);
                std::process::exit(ParsExitCode::Error.into());
            }
        }
    } else {
        ParsConfig::default()
    };

    let raw_args: Vec<String> = env::args().collect();
    let args = fix_args(raw_args);
    let cli_args = CliParser::parse_from(args);

    if let Err((code, e)) = parser::handle_cli(config, cli_args) {
        eprintln!("{}", e);
        debug!("Error: {:?}", e);
        std::process::exit(code);
    }
}
