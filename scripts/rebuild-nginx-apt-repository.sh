#!/bin/bash

set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
repo_dir="${1:-${APT_REPO_ROOT:-$project_dir/repo}}"
gpg_home="${2:-${APT_REPO_GPG_HOME:-$project_dir/repo-gpg}}"
components="${APT_REPO_COMPONENTS:-${APT_REPO_COMPONENT:-main oldcpu}}"
releases="${APT_REPO_RELEASES:-22.04 24.04 26.04}"
architectures="${APT_REPO_ARCHITECTURES:-amd64 arm64}"
key_selector="${APT_REPO_KEY_ID:-}"
secret_key_listing=""

for command_name in apt-ftparchive awk gpg gzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $command_name" >&2
        exit 1
    fi
done

if [ ! -d "$repo_dir/pool" ]; then
    echo "ERROR: APT pool not found: $repo_dir/pool" >&2
    exit 1
fi
if [ ! -d "$gpg_home" ]; then
    echo "ERROR: GPG home not found: $gpg_home" >&2
    exit 1
fi

repo_dir="$(cd "$repo_dir" && pwd)"
gpg_home="$(cd "$gpg_home" && pwd)"

if [ -z "$key_selector" ]; then
    if ! secret_key_listing="$(gpg --no-permission-warning --homedir "$gpg_home" --list-secret-keys --with-colons 2>&1)"; then
        echo "ERROR: cannot read the repository signing key from $gpg_home" >&2
        printf '%s\n' "$secret_key_listing" >&2
        echo "Check for stale $gpg_home/S.gpg-agent* sockets left by a container." >&2
        exit 1
    fi
    key_selector="$(printf '%s\n' "$secret_key_listing" | awk -F: '$1 == "fpr" { print $10; exit }')"
fi
if [ -z "$key_selector" ]; then
    echo "ERROR: no repository signing key found in $gpg_home" >&2
    exit 1
fi

for release in $releases; do
    for component in $components; do
        mkdir -p "$repo_dir/pool/$component"
        for arch in $architectures; do
            arch_dir="$repo_dir/dists/$release/$component/binary-$arch"
            mkdir -p "$arch_dir"
            (
                cd "$repo_dir"
                apt-ftparchive packages "pool/$component" | awk -v arch="$arch" -v release="~ubuntu$release" -v component="$component" '
                    BEGIN {
                        RS = ""
                        ORS = "\n\n"
                        expected_release = release (component == "oldcpu" ? "~oldcpu" : "")
                    }
                    $0 ~ "\nArchitecture: " arch "(\n|$)" && $0 ~ "\nVersion: [^\n]*" expected_release "(\n|$)" { print }
                ' > "dists/$release/$component/binary-$arch/Packages"
                gzip -9fk "dists/$release/$component/binary-$arch/Packages"
            )
        done
    done

    (
        cd "$repo_dir"
        apt-ftparchive \
            -o APT::FTPArchive::Release::Origin="Custom nginx packages" \
            -o APT::FTPArchive::Release::Label="Custom nginx packages" \
            -o APT::FTPArchive::Release::Suite="$release" \
            -o APT::FTPArchive::Release::Codename="$release" \
            -o APT::FTPArchive::Release::Architectures="$architectures" \
            -o APT::FTPArchive::Release::Components="$components" \
            -o APT::FTPArchive::Release::Description="Custom nginx packages" \
            release "dists/$release" > "dists/$release/Release"
    )

    gpg --batch --yes --no-permission-warning --homedir "$gpg_home" --armor --detach-sign --local-user "$key_selector" \
        --output "$repo_dir/dists/$release/Release.gpg" "$repo_dir/dists/$release/Release"
    gpg --batch --yes --no-permission-warning --homedir "$gpg_home" --clearsign --local-user "$key_selector" \
        --output "$repo_dir/dists/$release/InRelease" "$repo_dir/dists/$release/Release"
done

gpg --batch --yes --no-permission-warning --homedir "$gpg_home" --output "$repo_dir/nginx-repo-signing-key.asc" \
    --armor --export "$key_selector"

echo "OK: APT repository metadata rebuilt and signed"
