#!/bin/sh
set -eu

repo_ref=${MINTY_REF:-main}
base_url=${MINTY_BASE_URL:-"https://raw.githubusercontent.com/cafeshop-ai/minty/$repo_ref"}
codex_home=${CODEX_HOME:-"$HOME/.codex"}
target="$codex_home/pets/minty"
download_dir=$(mktemp -d "${TMPDIR:-/tmp}/minty-install.XXXXXX")
install_id=$$
pending_pet="$target/.pet.json.$install_id.tmp"
pending_sprite="$target/.spritesheet.webp.$install_id.tmp"

cleanup() {
    rm -rf "$download_dir"
    rm -f "$pending_pet" "$pending_sprite"
}
trap cleanup EXIT HUP INT TERM

download() {
    url=$1
    output=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output"
    else
        echo "Minty installer requires curl or wget." >&2
        exit 1
    fi
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "Minty installer requires sha256sum or shasum." >&2
        exit 1
    fi
}

for file in pet.json spritesheet.webp checksums.sha256; do
    download "$base_url/$file" "$download_dir/$file"
done

seen_pet=0
seen_sprite=0
while read -r expected file; do
    case "$file" in
        pet.json) seen_pet=1 ;;
        spritesheet.webp) seen_sprite=1 ;;
        *) echo "Invalid checksum entry: $file" >&2; exit 1 ;;
    esac
    actual=$(sha256_file "$download_dir/$file")
    if [ "$actual" != "$expected" ]; then
        echo "Checksum mismatch for $file" >&2
        exit 1
    fi
done < "$download_dir/checksums.sha256"

if [ "$seen_pet" -ne 1 ] || [ "$seen_sprite" -ne 1 ]; then
    echo "Checksum manifest is incomplete." >&2
    exit 1
fi

grep -Eq '"id"[[:space:]]*:[[:space:]]*"minty"' "$download_dir/pet.json"
grep -Eq '"spriteVersionNumber"[[:space:]]*:[[:space:]]*2' "$download_dir/pet.json"
grep -Eq '"spritesheetPath"[[:space:]]*:[[:space:]]*"spritesheet.webp"' "$download_dir/pet.json"

mkdir -p "$target"
cp "$download_dir/pet.json" "$pending_pet"
cp "$download_dir/spritesheet.webp" "$pending_sprite"
mv -f "$pending_sprite" "$target/spritesheet.webp"
mv -f "$pending_pet" "$target/pet.json"

echo "Minty installed to $target"
echo "Open Codex Settings > Pets, refresh the list, and select Minty."
