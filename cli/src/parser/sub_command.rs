use clap::Subcommand;

#[derive(Subcommand)]
pub enum SubCommands {
    Init {
        #[arg(short = 'p', long = "path", value_name = "sub-folder")]
        path: Option<String>,

        #[arg(required = true)]
        gpg_ids: String,
    },

    #[command(alias = "list")]
    Ls {
        subfolder: Option<String>,
    },

    Grep {
        #[arg(trailing_var_arg = true, required = true)]
        args: Vec<String>,
    },

    #[command(alias = "search")]
    Find {
        #[arg(required = true)]
        names: Vec<String>,
    },

    Show {
        #[arg(
            short = 'c',
            long = "clip",
            value_name = "line-number",
            default_missing_value = "1",
            num_args = 0..=1
        )]
        clip: Option<u32>,

        #[arg(
            short = 'q',
            long = "qrcode",
            value_name = "line-number",
            default_missing_value = "1",
            num_args = 0..=1
        )]
        qrcode: Option<u32>,

        pass_name: String,
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
        pass_name: String,
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

        pass_length: Option<u32>,
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
