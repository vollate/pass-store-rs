use clap::Subcommand;

#[derive(Subcommand)]
pub enum SubCommands {
    /// Initialize new password storage using provided GPG key IDs.
    Init {
        /// Specific subfolder to assign a GPG id (optional).
        #[arg(short, long, value_name = "sub-folder")]
        path: Option<String>,
        /// One or more GPG key IDs for encryption.
        #[arg(required = true)]
        gpg_ids: Vec<String>,
    },

    /// List names of passwords in a subfolder.
    #[command(alias = "list")]
    Ls {
        /// Subfolder to list (optional).
        subfolder: Option<String>,
    },

    /// Search inside decrypted password files using grep options.
    Grep {
        /// GREPOPTIONS and search string. The last argument is the search string.
        #[arg(trailing_var_arg = true, required = true)]
        args: Vec<String>,
    },

    /// Find password entries matching the given names.
    #[command(alias = "search")]
    Find {
        /// Password names to search for.
        #[arg(required = true)]
        names: Vec<String>,
    },

    /// Decrypt and print a password (or copy/QR-code it).
    Show {
        /// Copy the first (or specified) line to the clipboard instead of printing.
        #[arg(
            short = 'c',
            long = "clip",
            value_name = "line-number",
            default_missing_value = "1",
            num_args = 0..=1
        )]
        clip: Option<u32>,

        /// Display a QR code for the password.
        #[arg(
            short = 'q',
            long = "qrcode",
            value_name = "line-number",
            default_missing_value = "1",
            num_args = 0..=1
        )]
        qrcode: Option<u32>,

        /// Name of the password entry.
        pass_name: String,
    },

    /// Insert a new password into the store.
    #[command(alias = "add")]
    Insert {
        /// Name of the password entry.
        pass_name: String,

        /// Echo the password when entering (instead of hiding input).
        #[arg(short = 'e', long = "echo", conflicts_with = "multiline")]
        echo: bool,

        /// Read multiple lines until EOF (or Ctrl+D) is reached.
        #[arg(short = 'm', long = "multiline", conflicts_with = "echo")]
        multiline: bool,

        /// Force insertion without prompting.
        #[arg(short = 'f', long = "force")]
        force: bool,
    },

    /// Edit an existing password using the default text editor.
    Edit {
        /// Name of the password entry to edit.
        pass_name: String,
    },

    /// Generate a new password and insert it into the store.
    Generate {
        /// Do not include symbols in the generated password.
        #[arg(short = 'n', long = "no-symbols")]
        no_symbols: bool,

        /// Copy the generated password to the clipboard.
        #[arg(short = 'c', long = "clip")]
        clip: bool,

        /// Replace only the first line of the password file (in-place update).
        #[arg(short = 'i', long = "in-place", conflicts_with = "force")]
        in_place: bool,

        /// Force generation without prompting.
        #[arg(short = 'f', long = "force", conflicts_with = "in_place")]
        force: bool,

        /// Name of the password entry.
        pass_name: String,

        /// Optional length of the password to generate.
        pass_length: Option<u32>,
    },

    /// Remove a password from the store.
    #[command(alias = "remove", alias = "delete")]
    Rm {
        /// Remove recursively if the entry is a directory.
        #[arg(short = 'r', long = "recursive")]
        recursive: bool,

        /// Force removal without prompting.
        #[arg(short = 'f', long = "force")]
        force: bool,

        /// Name of the password entry to remove.
        pass_name: String,
    },

    /// Rename a password or directory.
    #[command(alias = "rename")]
    Mv {
        /// Force renaming by silently overwriting the destination if it exists.
        #[arg(short = 'f', long = "force")]
        force: bool,

        /// Current path of the password entry.
        old_path: String,

        /// New path for the password entry.
        new_path: String,
    },

    /// Copy a password or directory.
    #[command(alias = "copy")]
    Cp {
        /// Force copying by silently overwriting the destination if it exists.
        #[arg(short = 'f', long = "force")]
        force: bool,

        /// Source path of the password entry.
        old_path: String,

        /// Destination path for the password entry.
        new_path: String,
    },

    /// Pass git commands to the password store's git repository.
    Git {
        /// Git command and its arguments.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
}
