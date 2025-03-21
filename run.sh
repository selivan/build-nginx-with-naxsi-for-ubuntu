#!/bin/bash

cd /opt

set -x
set -e

function fail() {
    echo "ERROR: build failed. See container logs"
}
trap fail ERR

# CHECK THAT REQUIRED VARIABLES ARE SET

test -n "$NGINX_VERSION"
NGINX_BUILD_VERSION="10$NGINX_VERSION"
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


: > nginx-build-module-args
echo -n "libc6,libssl3" > dependencies

cat nginx_modules.yaml | yq --output-format json | jq -c '.dymanic_modules[]' | while read -r i; do

    name=$(echo "$i" | jq -r '.name')
    url=$(echo "$i" | jq -r '.url')
    build_deps=$(echo "$i" | jq -r '.build_deps // ""')
    deps=$(echo "$i" | jq -r '.deps // ""')
    src_subdir=$(echo "$i" | jq -r '.src_subdir // ""')
    config=$(echo "$i" | jq -r '.config // ""')
    config_dest=$(echo "$i" | jq -r '.config_dest // ""')

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

checkinstall --nodoc --deldesc --pkgname=nginx --maintainer=selivan@github --pkgversion=${NGINX_BUILD_VERSION} --requires=${DEPENDENCIES} --include=../checkinstall-files-to-add -y

cp -f *.deb ../packages

echo "OK: build successful. Check packages dir"
