# nginx-naxsi-build

Dockerfile to build Ubuntu packages of [Nginx](https://nginx.org/en/download.html) web server with additional modules, defined in `nginx_modules.yaml`.

Provided `nginx_modules.yaml` file adds this modules:

* [Naxsi](https://github.com/wargio/naxsi) - WAF(Web Application Firewall) module
* [geoip2](https://github.com/leev/ngx_http_geoip2_module) - geoip module for new maxmind format
* [http-echo](https://github.com/openresty/echo-nginx-module/) - add echo and other useful directives
* [http-headers-more](https://github.com/openresty/headers-more-nginx-module/) - set and clear all input and ouput headers

Custom package is set to have version with "10" prefix over actual nginx version(like 101.26.1 instead of 1.26.1) so it always have preference over system packages.

[checkinstall](https://checkinstall.izto.org/) is used, which is old and probably not updated anymore, but very simple and convenient.

# Usage

```bash
BASE_IMAGE="ubuntu:24.04"
NGINX_VERSION="1.28.2"
NGINX_CC_OPT="-march=x86-64-v3"
docker build . -t build-nginx --build-arg NGINX_VERSION="$NGINX_VERSION" --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg NGINX_CC_OPT="$NGINX_CC_OPT"
# --rm: do not leave the container hanging in system
docker run --rm -it -v "$(pwd)":/opt build-nginx
# built packages are now in packages directory
```

## nginx_modules.yaml

Modules versions and download URLs are in `nginx_modules.yaml`.

* `name` should be name of `*.so` file after building module
* `url`  URL to download module. It can have `$version` placeholder that will be replaced by `version`
* `version`  Can be used in URL as `$version`
* `version_use_github_latest_release`  if `true` and URL is github link: `version` will be generated for latest available release
* `version_use_github_latest_tag`  if `true` and URL is github link: `version` will be generated for latest available tag
* `deps`  packages that should be added to depencdencies of built package, like `libfoobar`
* `build_deps`  packages required for building process, like `libfoobar-dev`
* `src_subdir`  directory inside package archive used as argument for `--add-dynamic-module` configure option. Usually not necessary
* `config`, `config_dest`  That file(or directory) will be copied to that destination and added to built package

## nginx build arguments

Modify variable `NGINX_BUILD_ARGS` in Dockerfile. It has all necessary nginx build args except all `--add-dynamic-module=` ones.

Or add docker argument `NGINX_CC_OPT` for additional gcc arguments:

`--build-arg NGINX_CC_OPT="-march=x86-64-v3"`

Note: you can use command `ld.so --help` (see the end of the output) to detect supported [x86-64 microarchtecture level](https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels) for your hardware.

To get default nginx build args for your system:

```bash
docker run --rm -it ubuntu:24.04
apt update; apt install --yes --install-recommends=no nginx-light
nginx -V 2>&1 | grep "configure arguments:" | cut -d ":" -f2- | sed -e "s#/build/nginx-[A-Za-z0-9]*/#./#g" | sed 's/--add-dynamic-module=[A-Za-z0-9\/\._-]*//g'
```
## nginx configs

Debian style nginx configs are copied from `nginx_configs`. Change if necessary.

Note: module loading directives are present in modules-enabled subdirectory.

# Debug

```bash
docker run --rm -it -v "$(pwd)":/opt -w /opt --entrypoint /bin/bash build-nginx
# inside container
./run.sh # fix whatever is broken
```
