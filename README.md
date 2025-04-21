# Pars


<!-- vim-markdown-toc GFM -->

- [Usage](#usage)
- [Dependencies](#dependencies)
- [Installation](#installation)
  - [Package Manager](#package-manager)
    - [Arch Linux](#arch-linux)
    - [MacOS](#macos)
    - [Windows](#windows)

<!-- vim-markdown-toc -->

`pars` is a cross platform [zx2c4-pass](https://www.passwordstore.org/) compatibility cli tool for managing password store.
## Usage

`pars` is fully compatible with `pass` and the commands are the same. Here are some examples:

```sh
# Initialize the password store
pars init <your-gpg-id>

# Add a password
pars insert <path/to/password>

# Generate a password
pars generate <path/to/password> <length> # -c for copy to clipboard

# Show a password
pars show <path/to/password> # -c for copy to clipboard/ -q to show password's qr code

# Edit a password
pars edit <path/to/password>
```


## Dependencies

To use `pars` you need to make sure your system has the following dependencies installed:

- `gpg2`: for encryption and decryption(gnupg, openpgp or other program that implements pgp standard)
- `git`: for version control

For more information on how to install these dependencies, please refer to the [Installation](#installation) section.

## Installation

### Package Manager

#### Arch Linux

You can install `pars` from the AUR using your favorite AUR helper. For example, with `yay` 

```sh
yay -S pars
```
or `paru`:
```sh
paru -S pars
```

#### MacOS

You can install `pars` from the [homebrew](https://brew.sh/) using the following command:

```sh
brew tap pars
brew install pars
```
<!--todo-->

#### Windows

You can install `pars` from the [scoop](https://scoop.sh/) using the following command:

```sh
scoop add bucket
scoop install pars
```
<!--todo-->

