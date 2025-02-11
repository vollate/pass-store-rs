mod command;
mod constants;
mod parser;
mod util;

use clap::Parser;
use parser::CliParser;

fn main() {
    // Parse the command-line arguments.
    let cli = CliParser::parse();
    // Delegate to the CLI handler.
    parser::handle_cli(cli);
}
