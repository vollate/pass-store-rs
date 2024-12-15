use std::fs::File;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

fn decrypt_file(executable: &str, input_file: &str) -> Result<String, Box<dyn std::error::Error>> {
    let output = Command::new(executable)
        .arg("--decrypt")
        .arg(input_file)
        .output()?;

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
    use super::*;
    use std::fs::write;
    use std::process::Command;

    #[test]
    fn test_decrypt_file() {
        let encrypted_file = "test_encrypted.gpg";
        let decrypted_content = "This is a test";

        let mut encrypt_cmd = Command::new("gpg")
            .arg("--symmetric")
            .arg("--cipher-algo")
            .arg("AES256")
            .arg("--output")
            .arg(encrypted_file)
            .stdin(Stdio::piped())
            .spawn()
            .expect("Failed to start gpg process");

        {
            let stdin = encrypt_cmd.stdin.as_mut().expect("Failed to open stdin");
            stdin
                .write_all(decrypted_content.as_bytes())
                .expect("Failed to write to stdin");
        }

        encrypt_cmd.wait().expect("Failed to wait on gpg process");

        // Test the decrypt_file function
        let result = decrypt_file("gpg",encrypted_file);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), decrypted_content);

        // Clean up the temporary file
        std::fs::remove_file(encrypted_file).expect("Failed to delete temporary file");
    }
}
