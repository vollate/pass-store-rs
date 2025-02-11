#!/bin/env bash
TARGET_DIRS=("core" "cli")

if not [ -d '.git' ]; then
    echo "Not a git repository, please use at the root of a git repository"
    exit 1
fi

git add -A
cargo fix --allow-staged
cargo fmt

for dir in "${TARGET_DIRS[@]}"; do
    cd $dir
    echo -e "====== Testing $dir ======\n"
    cargo clippy
    cargo test
    cd ..
done

git add -A
