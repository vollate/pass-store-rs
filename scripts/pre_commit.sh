#!/bin/env bash
TARGET_DIRS=("core" "cli")

if ! [ -d '.git' ]; then
    echo "Not a git repository, please use at the root of a git repository"
    exit 1
fi

git add -A
cargo fix --allow-staged -q
if [ $? -ne 0 ]; then
    echo "cargo fix failed"
    exit $?
fi
cargo fmt
if [ $? -ne 0 ]; then
    echo "cargo fmt failed"
    exit $?
fi

for dir in "${TARGET_DIRS[@]}"; do
    cd "$dir" || exit
    echo -e "\n\n============================== Testing $dir ==============================\n\n"
    cargo clippy --fix --allow-dirty
    if [ $? -ne 0 ]; then
        echo "cargo clippy failed in $dir"
        cd ..
        exit $?
    fi
    cargo test -- --include-ignored
    if [ $? -ne 0 ]; then
        echo "cargo test failed in $dir"
        cd ..
        exit $?
    fi
    cd ..
done

git add -A
