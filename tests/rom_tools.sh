#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PACKER="$PROJECT_ROOT/build_arm/tools/rom_packer"
INSPECTOR="$PROJECT_ROOT/build_arm/tools/rom_inspect"

[ -x "$PACKER" ] && [ -x "$INSPECTOR" ] || {
    echo 'Build the ARM target before running the ROM tool tests.' >&2
    exit 1
}

TEST_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/languas-rom-test.XXXXXX")
trap 'rm -rf -- "$TEST_DIRECTORY"' EXIT HUP INT TERM

expect_failure() {
    if "$@"; then
        echo "expected failure: $*" >&2
        exit 1
    fi
}

printf '\000\020\000\040\011\000\000\000\000\277' > "$TEST_DIRECTORY/bootex.bin"
printf 'LGUS\000\001\002\000\014\000\000\000\000\277' > "$TEST_DIRECTORY/languas.bin"

"$PACKER" "$TEST_DIRECTORY/bootex.bin" "$TEST_DIRECTORY/languas.bin" \
    "$TEST_DIRECTORY/valid.rom"
"$INSPECTOR" verify "$TEST_DIRECTORY/valid.rom"
[ "$(wc -c < "$TEST_DIRECTORY/valid.rom")" -eq 4110 ] || {
    echo 'minimal valid ROM must be 4110 bytes' >&2
    exit 1
}

dd if=/dev/zero of="$TEST_DIRECTORY/bootex-too-large.bin" bs=4097 count=1 2>/dev/null
expect_failure "$PACKER" "$TEST_DIRECTORY/bootex-too-large.bin" \
    "$TEST_DIRECTORY/languas.bin" "$TEST_DIRECTORY/bad-bootex.rom"

printf '\000\020\000\040\011\000\000\000' > "$TEST_DIRECTORY/bootex-truncated-handler.bin"
expect_failure "$PACKER" "$TEST_DIRECTORY/bootex-truncated-handler.bin" \
    "$TEST_DIRECTORY/languas.bin" "$TEST_DIRECTORY/bad-handler.rom"

dd if=/dev/zero of="$TEST_DIRECTORY/languas-too-large.bin" bs=28673 count=1 2>/dev/null
expect_failure "$PACKER" "$TEST_DIRECTORY/bootex.bin" \
    "$TEST_DIRECTORY/languas-too-large.bin" "$TEST_DIRECTORY/bad-languas.rom"

cp "$TEST_DIRECTORY/valid.rom" "$TEST_DIRECTORY/bad-profile.rom"
printf '\004' | dd of="$TEST_DIRECTORY/bad-profile.rom" bs=1 seek=4102 conv=notrunc 2>/dev/null
expect_failure "$INSPECTOR" verify "$TEST_DIRECTORY/bad-profile.rom"

cp "$TEST_DIRECTORY/valid.rom" "$TEST_DIRECTORY/bad-stack.rom"
printf '\040' | dd of="$TEST_DIRECTORY/bad-stack.rom" bs=1 seek=1 conv=notrunc 2>/dev/null
expect_failure "$INSPECTOR" verify "$TEST_DIRECTORY/bad-stack.rom"

echo 'ROM tool boundary tests passed.'
