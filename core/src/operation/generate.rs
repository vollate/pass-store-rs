use std::error::Error;
use std::io::{Read, Write};
use std::path::Path;

use secrecy::SecretString;

use crate::pgp::PGPClient;
use crate::util::fs_utils::is_subpath_of;

pub struct PasswdGenerateConfig {
    no_symbols: bool,
    in_place: bool,
    force: bool,
    length: usize,
}

pub fn generate_io<I, O, E>(
    client: &PGPClient,
    root: &Path,
    pass_name: &str,
    config: &PasswdGenerateConfig,
    stdin: &mut I,
    stdout: &mut O,
    stderr: &mut E,
) -> Result<SecretString, Box<dyn Error>>
where
    I: Read,
    O: Write,
    E: Write,
{
    let pass_path = root.join(pass_name);
    
    if !is_subpath_of(root, &pass_path)? {
        let err_msg =
            format!("'{}' is not the subpath of the root path '{}'", pass_name, root.display());
        writeln!(stderr, "{}", err_msg)?;
        return Err(err_msg.into());
    }

    if config.in_place && config.force {
        let err_msg = format!("Cannot use both --in-place and --force");
        writeln!(stderr, "{}", err_msg)?;
        return Err(err_msg.into());
    }

    
    todo!()
}
