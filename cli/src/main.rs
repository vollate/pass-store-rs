mod command;
mod constants;
mod parser;
mod util;

use clap::Parser;
use parser::CliParser;

fn main() {
    let cli = CliParser::parse();
    parser::handle_cli(cli);
}
