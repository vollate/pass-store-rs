use clap::Subcommand;

#[derive(Subcommand)]
pub enum SubCommands {
    Init {
        #[arg(short = 'p', long = "path", value_name = "sub-folder")]
        path: Option<String>,

        #[arg(required = true)]
        gpg_ids: Vec<String>,
    },

    Grep {
        search_string: String,
    },

    #[command(alias = "search")]
    Find {
        #[arg(required = true)]
        names: Vec<String>,
    },

    #[command(alias = "show", alias = "list")]
    Ls {
        #[arg(
            short = 'c',
            long = "clip",
            value_name = "line-number",
            default_missing_value = "0",
            num_args = 0..=1
        )]
        clip: Option<usize>,

        #[arg(
            short = 'q',
            long = "qrcode",
            value_name = "line-number",
            default_missing_value = "0",
            num_args = 0..=1
        )]
        qrcode: Option<usize>,

        pass_name: Option<String>,
    },

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

    Edit {
        target_pass: String,
    },

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

    #[command(alias = "remove", alias = "delete")]
    Rm {
        #[arg(short = 'r', long = "recursive")]
        recursive: bool,

        #[arg(short = 'f', long = "force")]
        force: bool,

        pass_name: String,
    },

    #[command(alias = "rename")]
    Mv {
        #[arg(short = 'f', long = "force")]
        force: bool,

        old_path: String,

        new_path: String,
    },

    #[command(alias = "copy")]
    Cp {
        #[arg(short = 'f', long = "force")]
        force: bool,

        old_path: String,

        new_path: String,
    },

    Git {
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
}
