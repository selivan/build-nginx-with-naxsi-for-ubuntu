# nginx-naxsi-build

Dockerfile to build Ubuntu packages of [Nginx](https://nginx.org/) web server with additional modules, defined in `nginx_modules.yaml`.

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
docker build . -t build-nginx --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg NGINX_CC_OPT="-march=x86-64-v3"
# --rm: do not leave the container hanging in system
docker run --rm -it -v "$(pwd)":/opt build-nginx
# built packages are now in packages directory
```

## nginx modules

Modules versions and download URLs are in `nginx_modules.yaml`.

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
