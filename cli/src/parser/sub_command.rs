use clap::Subcommand;

#[derive(Subcommand)]
pub enum SubCommands {
    #[clap(about = "Initialize a new password store or reinitialize an existing one/sub-folder.")]
    Init {
        #[arg(short = 'p', long = "path", value_name = "sub-folder")]
        path: Option<String>,

        #[arg(required = true)]
        gpg_ids: Vec<String>,
    },

    #[clap(about = "Search for a string in all files, regex is supported")]
    Grep { search_string: String },

    #[clap(about = "Find a password by name")]
    #[command(alias = "search")]
    Find {
        #[arg(required = true)]
        names: Vec<String>,
    },

    #[clap(about = "List all passwords in the store or a sub-folder")]
    #[command(alias = "list")]
    Ls { sub_folder: Option<String> },

    #[clap(about = "Show a password, optionally clip or qrcode it")]
    Show {
        #[arg(
            short = 'c',
            long = "clip",
            value_name = "line-number",
            default_missing_value = "1",
            num_args = 0..=1
        )]
        clip: Option<usize>,

        #[arg(
            short = 'q',
            long = "qrcode",
            value_name = "line-number",
            default_missing_value = "1",
            num_args = 0..=1
        )]
        qrcode: Option<usize>,

        pass_name: Option<String>,
    },

    #[clap(about = "Insert a new password")]
    #[command(alias = "add")]
    Insert {
        pass_name: String,

        #[arg(short = 'e', long = "echo", conflicts_with = "multiline")]
        echo: bool,

        #[arg(short = 'm', long = "multiline", conflicts_with = "echo")]
        multiline: bool,

        #[arg(short = 'f', long = "force")]
        force: bool,
    },

    #[clap(about = r#"Edit a password using specified editor.
You can set the editor using the `PARS_EDITOR` environment variable or set it in config file."#)]
    Edit { target_pass: String },

    #[clap(
        about = r#"Generate a new password of pass-length (or 20 if unspecified) with optionally no symbols.
Optionally put it on the clipboard and clear board after 45 seconds.
Prompt before overwriting existing password unless forced.
Optionally replace only the first line of an existing file with a new password."#
    )]
    Generate {
        #[arg(short = 'n', long = "no-symbols")]
        no_symbols: bool,

        #[arg(short = 'c', long = "clip")]
        clip: bool,

        #[arg(short = 'i', long = "in-place", conflicts_with = "force")]
        in_place: bool,

        #[arg(short = 'f', long = "force", conflicts_with = "in_place")]
        force: bool,

        pass_name: String,

        pass_length: Option<usize>,
    },

    #[clap(about = r#"Remove a password or a sub-folder.
Optionally recursively."#)]
    #[command(alias = "remove", alias = "delete")]
    Rm {
        #[arg(short = 'r', long = "recursive")]
        recursive: bool,

        #[arg(short = 'f', long = "force")]
        force: bool,

        pass_name: String,
    },

    #[clap(about = r#"Move a password or a sub-folder frome old-path to new-path.
Optionally forcefully, selectively reencrypting."#)]
    #[command(alias = "rename")]
    Mv {
        #[arg(short = 'f', long = "force")]
        force: bool,

        old_path: String,

        new_path: String,
    },

    #[clap(
        about = "Copy a password or a sub-folder from old-path to new-path. Optionally forcefully."
    )]
    #[command(alias = "copy")]
    Cp {
        #[arg(short = 'f', long = "force")]
        force: bool,

        old_path: String,

        new_path: String,
    },

    #[clap(about = "Run a git command with the password store as the working directory.")]
    Git {
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
}
