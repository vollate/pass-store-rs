use std::path::PathBuf;
use std::{env, fs};

use anyhow::{anyhow, Error, Result};

use crate::parser::sub_command::{CompletionAction, ShellType};

const BASH_COMPLETION: &str = include_str!("../../../completion/bash/pars.bash");
const ZSH_COMPLETION: &str = include_str!("../../../completion/zsh/_pars");
const FISH_COMPLETION: &str = include_str!("../../../completion/fish/pars.fish");
const PWSH_COMPLETION_PSM1: &str = include_str!("../../../completion/pwsh/ParsCompletion.psm1");
const PWSH_COMPLETION_PSD1: &str = include_str!("../../../completion/pwsh/ParsCompletion.psd1");

const PARS_MARKER: &str = "# Added by pars completion";

fn detect_shell() -> Result<ShellType, Error> {
    // Check $SHELL env var
    if let Ok(shell_env) = env::var("SHELL") {
        let basename = shell_env.rsplit('/').next().unwrap_or(&shell_env);
        match basename {
            "bash" => return Ok(ShellType::Bash),
            "zsh" => return Ok(ShellType::Zsh),
            "fish" => return Ok(ShellType::Fish),
            _ => {}
        }
    }

    // On Windows or if $PSModulePath is set, try PowerShell
    if cfg!(windows) || env::var("PSModulePath").is_ok() {
        return Ok(ShellType::Powershell);
    }

    Err(anyhow!(
        "Could not detect shell. Please specify one with --shell (bash, zsh, fish, powershell)"
    ))
}

fn resolve_shell(shell: Option<ShellType>) -> Result<ShellType, Error> {
    match shell {
        Some(s) => Ok(s),
        None => detect_shell(),
    }
}

fn home_dir() -> Result<PathBuf, Error> {
    dirs::home_dir().ok_or_else(|| anyhow!("Could not determine home directory"))
}

fn generate(shell: &ShellType) {
    match shell {
        ShellType::Bash => {
            print!("{}", BASH_COMPLETION);
            eprintln!("\n# Usage: Add the following to your ~/.bashrc (or save to a file):");
            eprintln!("#   pars completion generate --shell bash >> ~/.bashrc");
            eprintln!("#");
            eprintln!("# Or save to the bash-completion directory (recommended):");
            eprintln!("#   pars completion generate --shell bash > ~/.local/share/bash-completion/completions/pars");
            eprintln!("#");
            eprintln!("# Alternatively, run `pars completion install` to do this automatically.");
        }
        ShellType::Zsh => {
            print!("{}", ZSH_COMPLETION);
            eprintln!("\n# Usage: Save to a directory in your $fpath:");
            eprintln!(
                "#   mkdir -p ~/.zfunc && pars completion generate --shell zsh > ~/.zfunc/_pars"
            );
            eprintln!("#");
            eprintln!("# Then ensure your ~/.zshrc contains:");
            eprintln!("#   fpath+=~/.zfunc");
            eprintln!("#   autoload -Uz compinit && compinit");
            eprintln!("#");
            eprintln!("# Alternatively, run `pars completion install` to do this automatically.");
        }
        ShellType::Fish => {
            print!("{}", FISH_COMPLETION);
            eprintln!("\n# Usage: Save to the fish completions directory:");
            eprintln!(
                "#   pars completion generate --shell fish > ~/.config/fish/completions/pars.fish"
            );
            eprintln!("#");
            eprintln!("# Fish will auto-load it on next shell start.");
            eprintln!("# Alternatively, run `pars completion install` to do this automatically.");
        }
        ShellType::Powershell => {
            print!("{}", PWSH_COMPLETION_PSM1);
            eprintln!("\n# Usage: Save as a PowerShell module:");
            eprintln!("#   Save the output to <Documents>/PowerShell/Modules/ParsCompletion/ParsCompletion.psm1");
            eprintln!("#   Then add `Import-Module ParsCompletion` to your $PROFILE");
            eprintln!("#");
            eprintln!("# Alternatively, run `pars completion install` to do this automatically.");
        }
    }
}

fn install_bash() -> Result<(), Error> {
    let completions_dir = dirs::data_local_dir()
        .unwrap_or_else(|| home_dir().unwrap().join(".local/share"))
        .join("bash-completion/completions");

    fs::create_dir_all(&completions_dir)?;
    let target = completions_dir.join("pars");
    fs::write(&target, BASH_COMPLETION)?;
    eprintln!("Installed bash completion to {}", target.display());
    Ok(())
}

fn install_zsh() -> Result<(), Error> {
    let home = home_dir()?;
    let zfunc_dir = home.join(".zfunc");
    fs::create_dir_all(&zfunc_dir)?;

    let target = zfunc_dir.join("_pars");
    fs::write(&target, ZSH_COMPLETION)?;
    eprintln!("Installed zsh completion to {}", target.display());

    // Ensure .zshrc has fpath and compinit lines
    let zshrc_path = home.join(".zshrc");
    let zshrc_content = fs::read_to_string(&zshrc_path).unwrap_or_default();

    let fpath_line = "fpath+=~/.zfunc";
    let compinit_line = "autoload -Uz compinit && compinit";

    let mut additions = String::new();

    if !zshrc_content.contains(fpath_line) {
        additions.push_str(&format!("\n{} {}\n", fpath_line, PARS_MARKER));
    }
    if !zshrc_content.contains("compinit") {
        additions.push_str(&format!("{} {}\n", compinit_line, PARS_MARKER));
    }

    if !additions.is_empty() {
        let mut new_content = zshrc_content;
        new_content.push_str(&additions);
        fs::write(&zshrc_path, new_content)?;
        eprintln!("Updated ~/.zshrc with fpath and compinit configuration");
    }

    Ok(())
}

fn install_fish() -> Result<(), Error> {
    let completions_dir = dirs::config_dir()
        .unwrap_or_else(|| home_dir().unwrap().join(".config"))
        .join("fish/completions");

    fs::create_dir_all(&completions_dir)?;
    let target = completions_dir.join("pars.fish");
    fs::write(&target, FISH_COMPLETION)?;
    eprintln!("Installed fish completion to {}", target.display());
    Ok(())
}

fn get_pwsh_module_dir() -> Result<PathBuf, Error> {
    // Check $PSModulePath first
    if let Ok(ps_module_path) = env::var("PSModulePath") {
        // Use the first user-writable path (typically the first entry)
        if let Some(first_path) = ps_module_path.split(if cfg!(windows) { ';' } else { ':' }).next()
        {
            let module_dir = PathBuf::from(first_path).join("ParsCompletion");
            return Ok(module_dir);
        }
    }

    // Fallback to Documents/PowerShell/Modules
    let docs_dir = dirs::document_dir()
        .ok_or_else(|| anyhow!("Could not determine documents directory for PowerShell modules"))?;
    Ok(docs_dir.join("PowerShell/Modules/ParsCompletion"))
}

fn get_pwsh_profile_path() -> PathBuf {
    if let Ok(profile) = env::var("PROFILE") {
        return PathBuf::from(profile);
    }

    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
    if cfg!(windows) {
        home.join("Documents/PowerShell/Microsoft.PowerShell_profile.ps1")
    } else {
        home.join(".config/powershell/Microsoft.PowerShell_profile.ps1")
    }
}

fn install_powershell() -> Result<(), Error> {
    let module_dir = get_pwsh_module_dir()?;
    fs::create_dir_all(&module_dir)?;

    let psm1_path = module_dir.join("ParsCompletion.psm1");
    let psd1_path = module_dir.join("ParsCompletion.psd1");

    fs::write(&psm1_path, PWSH_COMPLETION_PSM1)?;
    fs::write(&psd1_path, PWSH_COMPLETION_PSD1)?;
    eprintln!("Installed PowerShell module to {}", module_dir.display());

    // Add Import-Module to profile if not present
    let profile_path = get_pwsh_profile_path();
    let profile_content = fs::read_to_string(&profile_path).unwrap_or_default();

    let import_line = "Import-Module ParsCompletion";
    if !profile_content.contains(import_line) {
        if let Some(parent) = profile_path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut new_content = profile_content;
        new_content.push_str(&format!("\n{} {} \n", import_line, PARS_MARKER));
        fs::write(&profile_path, new_content)?;
        eprintln!("Added 'Import-Module ParsCompletion' to {}", profile_path.display());
    }

    Ok(())
}

fn uninstall_bash() -> Result<(), Error> {
    let completions_dir = dirs::data_local_dir()
        .unwrap_or_else(|| home_dir().unwrap().join(".local/share"))
        .join("bash-completion/completions");
    let target = completions_dir.join("pars");

    if target.exists() {
        fs::remove_file(&target)?;
        eprintln!("Removed bash completion from {}", target.display());
    } else {
        eprintln!("Bash completion is not installed");
    }
    Ok(())
}

fn uninstall_zsh() -> Result<(), Error> {
    let home = home_dir()?;
    let target = home.join(".zfunc/_pars");

    if target.exists() {
        fs::remove_file(&target)?;
        eprintln!("Removed zsh completion from {}", target.display());
    } else {
        eprintln!("Zsh completion is not installed");
    }

    // Remove marker-commented lines from .zshrc
    let zshrc_path = home.join(".zshrc");
    if zshrc_path.exists() {
        let content = fs::read_to_string(&zshrc_path)?;
        let new_content: String = content
            .lines()
            .filter(|line| !line.contains(PARS_MARKER))
            .collect::<Vec<_>>()
            .join("\n");
        if new_content != content {
            // Preserve trailing newline
            let final_content = if content.ends_with('\n') && !new_content.ends_with('\n') {
                format!("{}\n", new_content)
            } else {
                new_content
            };
            fs::write(&zshrc_path, final_content)?;
            eprintln!("Removed pars-related lines from ~/.zshrc");
        }
    }

    Ok(())
}

fn uninstall_fish() -> Result<(), Error> {
    let completions_dir = dirs::config_dir()
        .unwrap_or_else(|| home_dir().unwrap().join(".config"))
        .join("fish/completions");
    let target = completions_dir.join("pars.fish");

    if target.exists() {
        fs::remove_file(&target)?;
        eprintln!("Removed fish completion from {}", target.display());
    } else {
        eprintln!("Fish completion is not installed");
    }
    Ok(())
}

fn uninstall_powershell() -> Result<(), Error> {
    let module_dir = get_pwsh_module_dir()?;

    if module_dir.exists() {
        fs::remove_dir_all(&module_dir)?;
        eprintln!("Removed PowerShell completion module from {}", module_dir.display());
    } else {
        eprintln!("PowerShell completion is not installed");
    }

    // Remove marker-commented lines from profile
    let profile_path = get_pwsh_profile_path();
    if profile_path.exists() {
        let content = fs::read_to_string(&profile_path)?;
        let new_content: String = content
            .lines()
            .filter(|line| !line.contains(PARS_MARKER))
            .collect::<Vec<_>>()
            .join("\n");
        if new_content != content {
            let final_content = if content.ends_with('\n') && !new_content.ends_with('\n') {
                format!("{}\n", new_content)
            } else {
                new_content
            };
            fs::write(&profile_path, final_content)?;
            eprintln!("Removed pars-related lines from {}", profile_path.display());
        }
    }

    Ok(())
}

pub fn cmd_completion(action: CompletionAction) -> Result<(), (i32, Error)> {
    let result = match action {
        CompletionAction::Generate { shell } => {
            let shell_type = resolve_shell(shell).map_err(|e| (1, e))?;
            generate(&shell_type);
            Ok(())
        }
        CompletionAction::Install { shell } => {
            let shell_type = resolve_shell(shell).map_err(|e| (1, e))?;
            match shell_type {
                ShellType::Bash => install_bash(),
                ShellType::Zsh => install_zsh(),
                ShellType::Fish => install_fish(),
                ShellType::Powershell => install_powershell(),
            }
        }
        CompletionAction::Uninstall { shell } => {
            let shell_type = resolve_shell(shell).map_err(|e| (1, e))?;
            match shell_type {
                ShellType::Bash => uninstall_bash(),
                ShellType::Zsh => uninstall_zsh(),
                ShellType::Fish => uninstall_fish(),
                ShellType::Powershell => uninstall_powershell(),
            }
        }
    };

    result.map_err(|e| (1, e))
}
