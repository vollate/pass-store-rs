use std::error::Error;

use secrecy::SecretString;

pub(crate) fn copy_to_clip_board(
    p0: SecretString,
    p1: Option<usize>,
) -> Result<(), Box<dyn Error>> {
    todo!()
}
