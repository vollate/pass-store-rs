#!/bin/env bash
TARGET_DIRS=("core" "cli")

if not [ -d '.git' ]; then
    echo "Not a git repository, please use at the root of a git repository"
    exit 1
fi

git add -A
cargo clean
cargo fix --allow-staged -q
cargo fmt

for dir in "${TARGET_DIRS[@]}"; do
    cd "$dir" || exit
    echo -e "\n\n============================== Testing $dir ==============================\n\n"
    cargo clippy
    cargo test
    cd ..
done

git add -A
