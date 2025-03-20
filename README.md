# nginx-naxsi-build

Dockerfile to build Ubuntu packages of [Nginx](https://nginx.org/) web server with additional modules, defined in `nginx_modules.yaml`.

Provided `nginx_modules.yaml` file adds this modules:

* [Naxsi](https://github.com/wargio/naxsi) WAF(Web Application Firewall) module
* [geoip2](https://github.com/leev/ngx_http_geoip2_module), geoip module for new maxmind format
* [http-echo](https://github.com/openresty/echo-nginx-module/)
* [http-headers-more](https://github.com/openresty/headers-more-nginx-module/)

Custom package is set to have version with "10" prefix over actual nginx version(like 101.26.1 instead of 1.26.1) so it always have preference over system packages.

# Usage

```bash
BASE_IMAGE="ubuntu:24.04"
docker build . -t build-nginx --build-arg BASE_IMAGE="$BASE_IMAGE"
# --rm: do not leave the container hanging in system
docker run --rm -it -v "$(pwd)":/opt build-nginx
# built packages are now in packages directory
```

## nginx configs

Debian style nginx configs are copied from `nginx-configs`. Change if necessary.

Note: module loading directives are present in modules-enabled subdirectory.

## nginx build arguments

Modify variable NGINX_BUILD_ARGS in Dockerfile. It has all necessary nginx build args except all `--add-dynamic-module=` ones.

Or add docker argument `NGINX_MORE_BUILD_ARGS`:

`--build-arg NGINX_MORE_BUILD_ARGS="-march=x86-64-v3"`

Note: you cah use command `ld.so --help` (end of the output) to detect supported [x86-64 microarchtecture level](https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels) for your hardware.

To get default nginx build args for your system:

```
docker run --rm -it ubuntu:24.04
apt update; apt install --yes --install-recommends=no nginx-light
nginx -V 2>&1 | grep "configure arguments:" | cut -d ":" -f2- | sed -e "s#/build/nginx-[A-Za-z0-9]*/#./#g" | sed 's/--add-dynamic-module=[A-Za-z0-9\/\._-]*//g'
```

# Debug

```
docker run --rm -it -v "$(pwd)":/opt -w /opt --entrypoint /bin/bash build-nginx
# inside container
./run.sh # fix whatever is broken
```
