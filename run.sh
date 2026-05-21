#!/bin/bash

set -x
set -e

function fail() {
    echo "ERROR: build failed. See container logs"
}
trap fail ERR

function get_apt_repo_signing_key() {
    local gpg_home="$1"
    local key_name="${APT_REPO_KEY_NAME:-Custom nginx APT repository}"
    local key_email="${APT_REPO_KEY_EMAIL:-nginx-repo@example.invalid}"
    local key_selector="${APT_REPO_KEY_ID:-}"

    mkdir -p "$gpg_home"
    chmod 700 "$gpg_home"

    if [ -z "$key_selector" ]; then
        key_selector="$(gpg --no-permission-warning --homedir "$gpg_home" --list-secret-keys --with-colons 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
    fi

    if [ -z "$key_selector" ]; then
        cat > "$gpg_home/key.batch" <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $key_name
Name-Email: $key_email
Expire-Date: 0
%no-protection
%commit
EOF
        gpg --batch --no-permission-warning --homedir "$gpg_home" --generate-key "$gpg_home/key.batch"
        rm -f "$gpg_home/key.batch"
        key_selector="$(gpg --no-permission-warning --homedir "$gpg_home" --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')"
    fi

    echo "$key_selector"
}

function build_apt_repository() {
    local repo_dir="${APT_REPO_ROOT:-repo}"
    local gpg_home="${APT_REPO_GPG_HOME:-repo-gpg}"
    local component="${APT_REPO_COMPONENT:-main}"
    local releases="${APT_REPO_RELEASES:-$UBUNTU_RELEASE}"
    local architectures="${APT_REPO_ARCHITECTURES:-amd64 arm64}"
    local key_selector
    local release
    local arch
    local arch_dir

    mkdir -p "$repo_dir"
    key_selector="$(get_apt_repo_signing_key "$gpg_home")"

    for release in $releases; do
        for arch in $architectures; do
            arch_dir="$repo_dir/dists/$release/$component/binary-$arch"
            mkdir -p "$arch_dir"
            (
                cd "$repo_dir"
                apt-ftparchive packages pool | awk -v arch="$arch" -v release="~ubuntu$release" '
                    BEGIN { RS = ""; ORS = "\n\n" }
                    $0 ~ "\nArchitecture: " arch "(\n|$)" && $0 ~ "\nVersion: [^\n]*" release "(\n|$)" { print }
                ' > "dists/$release/$component/binary-$arch/Packages"
                gzip -9fk "dists/$release/$component/binary-$arch/Packages"
            )
        done

        (
            cd "$repo_dir"
            apt-ftparchive \
                -o APT::FTPArchive::Release::Origin="Custom nginx packages" \
                -o APT::FTPArchive::Release::Label="Custom nginx packages" \
                -o APT::FTPArchive::Release::Suite="$release" \
                -o APT::FTPArchive::Release::Codename="$release" \
                -o APT::FTPArchive::Release::Architectures="$architectures" \
                -o APT::FTPArchive::Release::Components="$component" \
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
}

function publish_debs_to_apt_pool() {
    local repo_dir="${APT_REPO_ROOT:-repo}"
    local pool_dir="$repo_dir/pool/main/n/nginx"
    local deb

    mkdir -p "$pool_dir"
    for deb in "$@"; do
        cp -f "$deb" "$pool_dir/"
    done
}

function normalize_nginx_deb_control() {
    local deb_path="$1"
    local deb_tmp_dir
    local control_file

    deb_tmp_dir="$(mktemp -d)"
    dpkg-deb -R "$deb_path" "$deb_tmp_dir"
    control_file="$deb_tmp_dir/DEBIAN/control"

    awk '
        /^[^[:space:]][^:]*:/ {
            field = $1
            sub(":", "", field)
            drop = (field == "Conflicts" || field == "Replaces" || field == "Provides")
        }
        !drop { print }
    ' "$control_file" > "$control_file.new"
    mv "$control_file.new" "$control_file"

    cat >> "$control_file" <<EOF
Conflicts: nginx-common, nginx-core, nginx-light, nginx-full, nginx-extras
Replaces: nginx-common, nginx-core, nginx-light, nginx-full, nginx-extras
Provides: nginx, nginx-common, httpd, httpd-cgi
EOF

    dpkg-deb -b "$deb_tmp_dir" "$deb_path"
    rm -rf "$deb_tmp_dir"
}

# CHECK THAT REQUIRED VARIABLES ARE SET

test -n "$NGINX_VERSION"
UBUNTU_RELEASE="${UBUNTU_RELEASE:-$(. /etc/os-release && echo "$VERSION_ID")}"
NGINX_BUILD_VERSION="10$NGINX_VERSION"
NGINX_PACKAGE_RELEASE="1~ubuntu${UBUNTU_RELEASE}"
# See https://nginx.org/en/download.html
NGINX_URL="https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"

test -n "$NGINX_BUILD_ARGS"

# UPDATE PACKAGES

# In case the docker image was built some time ago
apt update
apt dist-upgrade --yes
apt build-dep --yes --install-recommends=no nginx

# GET NGINX SOURCE

curl -L "$NGINX_URL" -o nginx.tar.gz
tar -xzf nginx.tar.gz
test -d nginx && rm -fr nginx
mv --no-target-directory nginx-"$NGINX_VERSION" nginx

: > dependencies
: > nginx-build-module-args
: > nginx-modules-versions
echo -n "libc6,libssl3" >> dependencies

python3 -c 'import json, sys, yaml; json.dump(yaml.safe_load(sys.stdin), sys.stdout)' < nginx_modules.yaml | jq -c '.dymanic_modules[]' | while read -r i; do

    name=$(echo "$i" | jq -r '.name')
    build_deps=$(echo "$i" | jq -r '.build_deps // ""')
    deps=$(echo "$i" | jq -r '.deps // ""')
    src_subdir=$(echo "$i" | jq -r '.src_subdir // ""')
    config=$(echo "$i" | jq -r '.config // ""')
    config_dest=$(echo "$i" | jq -r '.config_dest // ""')
    url=$(echo "$i" | jq -r '.url')
    version=$(echo "$i" | jq -r '.version')
    version_use_github_latest_release=$(echo "$i" | jq -r '.version_use_github_latest_release')
    version_use_github_latest_tag=$(echo "$i" | jq -r '.version_use_github_latest_tag')

    if [ "$version_use_github_latest_release" == "true" ]; then
        owner_repo="$(echo "$url" | cut -d/ -f4,5)"
        version=$(curl -s "https://api.github.com/repos/$owner_repo/releases/latest" | jq -r ".tag_name")
    fi

    if [ "$version_use_github_latest_tag" == "true" ]; then
        owner_repo="$(echo "$url" | cut -d/ -f4,5)"
        version=$(curl -s "https://api.github.com/repos/$owner_repo/tags?per_page=1" | jq -r ".[0].name")
    fi

    export version
    url="$(echo "$url" | envsubst)"

    echo "$name $version ($url)" >> nginx-modules-versions

    filename="${name}.archive"

    # DOWNLOAD MODULES SOURCES

    curl -L "$url" -o "$filename"
    test -d "modules/$name" && rm -fr "modules/$name"
    mkdir -p "modules/$name"
    # auppack auto-detects archive type
    aunpack -X "modules/$name" "$filename"

    # Copy files from directory inside archive if necessary
    subdirs=$(find "modules/$name" -mindepth 1 -maxdepth 1 -type d)
    subdirs_num=$(echo "$subdirs" | wc -l)
    if [ "$subdirs_num" -eq 1 -a -n "$subdirs" ]; then
        mv "$subdirs"/* "modules/$name"
        mv "$subdirs"/.* "modules/$name" || true
        rmdir "$subdirs"
    fi

    # SET SOME VARIABLES
    echo -n " --add-dynamic-module=../modules/$name/$src_subdir" >> nginx-build-module-args

    # INSTALL DEPENDENCIES
    if [ -n "$deps" ]; then
        echo -n ",$deps" >> dependencies
        apt install --yes --install-recommends=no $(echo $deps | tr ',' ' ')
    fi

    if [ -n "$build_deps" ]; then
        apt install --yes --install-recommends=no $(echo $build_deps | tr ',' ' ')
    fi

    # COPY MODULES CONFIGS
    if [ -n "$config_dest" ]; then
        pwd
        mkdir -p "$(dirname "$config_dest")"
        cp -arf "modules/$name/$config" "$config_dest"
    fi

    # CREATE CONFIGS FOR LOADING MODULES
    mkdir -p /usr/share/nginx/modules-available
    mkdir -p /etc/nginx/modules-enabled/
    echo "load_module modules/$name.so;" > /usr/share/nginx/modules-available/"$name".conf
    ln -sf /usr/share/nginx/modules-available/"$name".conf /etc/nginx/modules-enabled/50-"$name".conf

done

NGINX_BUILD_MODULE_ARGS="$(cat nginx-build-module-args)"
DEPENDENCIES="$(cat dependencies)"
rm -f nginx-build-module-args dependencies

## CONFIGURE NGINX

cd nginx

eval ./configure $NGINX_BUILD_ARGS $NGINX_MORE_BUILD_ARGS $NGINX_BUILD_MODULE_ARGS

cd ..

## COPY CUSTOM CONFIGS

cp -arf nginx_configs/* /
mkdir -p /etc/nginx/sites-enabled

# REPLACE CONFIGS IN NGINX SOURCES WITH OUR ONES TO PREVENT MAKEFILE FROM OVERRIDING OUR CONFIGS

cp -arf nginx_configs/etc/nginx/* nginx/conf

# CREATE SYMLINK TO FIX BROKEN MODULES SEARCH

ln -sf -T /usr/lib/nginx/modules /usr/share/nginx/modules

# CREATE LIST OF FILES TO INCLUDE FOR CHECKINSTALL

: > checkinstall-files-to-add

find nginx_configs -type f | sed 's/^nginx_configs//' >> checkinstall-files-to-add
find /usr/share/nginx/modules-available -type f >> checkinstall-files-to-add
find /etc/nginx/modules-enabled -type l >> checkinstall-files-to-add
# See NGINX_BUILD_ARGS in Dockerfile
mkdir -p /var/lib/nginx/{body,fastcgi,proxy,scgi,uwsgi}
find /var/lib/nginx -type d >> checkinstall-files-to-add
echo /usr/share/nginx/modules >> checkinstall-files-to-add

## BUILD

cd nginx

make

make install

# Some workarounds, no idea why this is necessary:
# make install works fine, but checkinstall fails without this
rm -f /etc/nginx/koi-utf /etc/nginx/koi-win /etc/nginx/win-utf
rm -f /usr/lib/nginx/modules/*.so
rm -f /etc/nginx/{fastcgi.conf,fastcgi_params,mime.types,nginx.conf,scgi_params,uwsgi_params}

# copy checkinstall files in build dir
cp -fr ../checkinstall/* .

: > description-pak
echo "Custom nginx build" >> description-pak
echo "Made using https://github.com/selivan/build-nginx-with-naxsi-for-ubuntu/" >> description-pak
echo "Added modules and versions:" >> description-pak
cat ../nginx-modules-versions >> description-pak

checkinstall --nodoc --deldesc --pkgname=nginx --maintainer=selivan@github --pkgversion=${NGINX_BUILD_VERSION} --pkgrelease=${NGINX_PACKAGE_RELEASE} --requires=${DEPENDENCIES} --include=../checkinstall-files-to-add -y

for deb in *.deb; do
    normalize_nginx_deb_control "$deb"
done

mkdir -p ../packages
cp -f *.deb ../packages
cd ..
publish_debs_to_apt_pool packages/*.deb
build_apt_repository

echo "OK: build successful. Check packages and repo dirs"
