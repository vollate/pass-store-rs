use std::error::Error;

use crate::pgp::PGPClient;

pub fn grep(client: &PGPClient) -> Result<Vec<String>, Box<dyn Error>> {
    todo!()
}
