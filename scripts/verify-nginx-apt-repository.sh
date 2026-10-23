#!/bin/bash

set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
repo_dir="${1:-${APT_REPO_ROOT:-$project_dir/repo}}"
gpg_home="${2:-${APT_REPO_GPG_HOME:-$project_dir/repo-gpg}}"
packages_dir="${PACKAGES_DIR:-$project_dir/packages}"
components="${APT_REPO_COMPONENTS:-${APT_REPO_COMPONENT:-main oldcpu}}"
releases="${APT_REPO_RELEASES:-22.04 24.04 26.04}"
architectures="${APT_REPO_ARCHITECTURES:-amd64 arm64}"

for command_name in awk cmp dpkg dpkg-deb find gpg grep gzip sha256sum; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $command_name" >&2
        exit 1
    fi
done

repo_dir="$(cd "$repo_dir" && pwd)"
gpg_home="$(cd "$gpg_home" && pwd)"

check_stable_package() {
    local deb_file="$1"
    local expected_component="${2:-}"
    local debian_version
    local nginx_version
    local nginx_minor
    local package_arch
    local package_name

    debian_version="$(dpkg-deb -f "$deb_file" Version)"
    package_name="$(dpkg-deb -f "$deb_file" Package)"
    package_arch="$(dpkg-deb -f "$deb_file" Architecture)"

    if [ "$package_name" != "nginx" ]; then
        echo "ERROR: unexpected package name in $deb_file: $package_name" >&2
        return 1
    fi

    if [[ "$debian_version" == *~oldcpu ]]; then
        if [ "$package_arch" != "amd64" ]; then
            echo "ERROR: oldcpu package is not amd64: $deb_file" >&2
            return 1
        fi
        if [ -n "$expected_component" ] && [ "$expected_component" != "oldcpu" ]; then
            echo "ERROR: oldcpu package is outside the oldcpu component: $deb_file" >&2
            return 1
        fi
    elif [ "$expected_component" = "oldcpu" ]; then
        echo "ERROR: package in the oldcpu component lacks the ~oldcpu suffix: $deb_file" >&2
        return 1
    fi

    nginx_version="${debian_version%%-*}"
    if [[ "$nginx_version" != 10* ]]; then
        echo "ERROR: unexpected package version in $deb_file: $debian_version" >&2
        return 1
    fi

    nginx_version="${nginx_version:2}"
    if [[ ! "$nginx_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: invalid nginx version in $deb_file: $debian_version" >&2
        return 1
    fi

    nginx_minor="${nginx_version#*.}"
    nginx_minor="${nginx_minor%%.*}"
    if [[ "$nginx_minor" == *[13579] ]] && [ "${I_REALLY_WANT_TO_BUILD_UNSTABLE:-}" != "1" ]; then
        echo "ERROR: mainline package found: $deb_file ($nginx_version)" >&2
        return 1
    fi
}

candidate_for_package() {
    local package_name="$1"
    local packages_file="$2"
    local candidate=""
    local version

    while read -r version; do
        if [ -z "$candidate" ] || dpkg --compare-versions "$version" gt "$candidate"; then
            candidate="$version"
        fi
    done < <(awk -v wanted="$package_name" '
        /^Package: / { package_name=$2 }
        /^Version: / && package_name == wanted { print $2 }
    ' "$packages_file")

    printf '%s\n' "$candidate"
}

if [ -d "$packages_dir" ]; then
    while IFS= read -r -d '' deb_file; do
        check_stable_package "$deb_file"
    done < <(find "$packages_dir" -type f -name '*.deb' -print0)
fi

for component in $components; do
    pool_dir="$repo_dir/pool/$component"
    if [ ! -d "$pool_dir" ]; then
        echo "ERROR: repository component pool is missing: $pool_dir" >&2
        exit 1
    fi
    while IFS= read -r -d '' deb_file; do
        check_stable_package "$deb_file" "$component"
    done < <(find "$pool_dir" -type f -name '*.deb' -print0)
done

oldcpu_required=0
if [ -d "$repo_dir/pool/oldcpu" ] && find "$repo_dir/pool/oldcpu" -type f -name '*.deb' -print -quit | grep -q .; then
    oldcpu_required=1
fi

for release in $releases; do
    release_components="$(awk -F ': ' '/^Components: / { print $2 }' "$repo_dir/dists/$release/Release")"
    if [ "$release_components" != "$components" ]; then
        echo "ERROR: unexpected Components in $release Release: $release_components" >&2
        exit 1
    fi

    for component in $components; do
        for arch in $architectures; do
            packages_file="$repo_dir/dists/$release/$component/binary-$arch/Packages"
            packages_gz="$packages_file.gz"
            test -f "$packages_file"
            test -s "$packages_gz"
            cmp "$packages_file" <(gzip -cd "$packages_gz")

            while read -r indexed_sha indexed_file; do
                case "$indexed_file" in
                    "pool/$component/"*) ;;
                    *)
                        echo "ERROR: package from another component is indexed in $packages_file: $indexed_file" >&2
                        exit 1
                        ;;
                esac
                printf '%s  %s\n' "$indexed_sha" "$repo_dir/$indexed_file" | sha256sum -c - >/dev/null
            done < <(awk '/^Filename: / { filename=$2 } /^SHA256: / { print $2, filename }' "$packages_file")

            nginx_candidate="$(candidate_for_package nginx "$packages_file")"
            if [ "$component" = "main" ]; then
                if [ -z "$nginx_candidate" ]; then
                    echo "ERROR: nginx candidate is missing from $packages_file" >&2
                    exit 1
                fi
            elif [ "$component" = "oldcpu" ]; then
                if [ "$arch" != "amd64" ] && [ -n "$nginx_candidate" ]; then
                    echo "ERROR: oldcpu nginx is indexed for $arch: $nginx_candidate" >&2
                    exit 1
                fi
                if [ "$arch" = "amd64" ] && [ "$oldcpu_required" = "1" ] && [ -z "$nginx_candidate" ]; then
                    echo "ERROR: oldcpu nginx candidate is missing from $packages_file" >&2
                    exit 1
                fi
            fi

            if [ -n "$nginx_candidate" ]; then
                echo "$release/$component/$arch nginx candidate: $nginx_candidate"
            fi
        done
    done

    (
        cd "$repo_dir/dists/$release"
        awk '/^SHA256:/{checksums=1; next} /^SHA512:/{checksums=0} checksums && index($3, "/") > 0 {print $1 "  " $3}' Release | sha256sum -c - >/dev/null
    )
    gpg --batch --no-permission-warning --homedir "$gpg_home" --verify "$repo_dir/dists/$release/InRelease"
    gpg --batch --no-permission-warning --homedir "$gpg_home" --verify \
        "$repo_dir/dists/$release/Release.gpg" "$repo_dir/dists/$release/Release"
done

echo "OK: APT repository components, indexes, packages, checksums, signatures, and stable-version policy verified"
