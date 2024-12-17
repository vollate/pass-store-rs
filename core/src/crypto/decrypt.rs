use std::process::Command;

fn decrypt_file(executable: &str, input_file: &str) -> Result<String, Box<dyn std::error::Error>> {
    let output = Command::new(executable).arg("--decrypt").arg(input_file).output()?;

    if output.status.success() {
        let decrypted = String::from_utf8(output.stdout)?;
        Ok(decrypted)
    } else {
        let error_message = String::from_utf8_lossy(&output.stderr);
        Err(format!("GPG decryption failed: {}", error_message).into())
    }
}

#[cfg(test)]
mod tests {
    use serial_test::serial;

    use super::super::key_management::gpg_key_gen_batch;
    use crate::util::test_utils::{
        clean_up_test_key, get_test_email, get_test_executable, gpg_key_gen_example_batch_input,
    };
    
    #[test]
    #[serial]
    fn test_decrypt_file() {
        gpg_key_gen_batch(&get_test_executable(), &gpg_key_gen_example_batch_input().unwrap())
            .unwrap();
        clean_up_test_key(&get_test_executable(), &get_test_email()).unwrap();
    }
}
