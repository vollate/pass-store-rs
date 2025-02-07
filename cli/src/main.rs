mod command;
mod parser;

use clap::Parser;
use parser::CliParser;

fn main() {
    // Parse the command-line arguments.
    let cli = CliParser::parse();
    // Delegate to the CLI handler.
    parser::handle_cli(cli);
}
