# nginx-naxsi-build

Dockerfile to build Ubuntu packages of [Nginx](https://nginx.org/) web server with [Naxsi](https://github.com/nbs-system/naxsi) WAF(Web Application Firewall).

It uses nginx packages from [Ubuntu nginx ppa](https://launchpad.net/~nginx/+archive/ubuntu/stable) as a template and builds `nginx-light` package with Naxsi support and couple of other modules(see `run.sh`). Custom packages are set to have version much larger than nginx version(like 101.16 instead of 1.16, see `Dockerfile`) so they always have preference on system with nginx ppa enabled.

Debian nginx build system is quite intricate, and this solution is ugly and lazily made, but it works and produces Debian-like Nginx packages with Naxsi support.

## Usage
Files for different os-releases should have names like run.**<os-codename>**.sh

```bash
BASE_IMAGE="ubuntu:xenial"
NAXSI_VERSION="1.3"
NGINX_BUILD_VERSION="101.18.0"
docker build . -t build-nginx --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg NAXSI_VERSION="$NAXSI_VERSION" --build-arg NGINX_BUILD_VERSION="$NGINX_BUILD_VERSION"
mkdir ~/nginx-packages
# --rm: do not leave the container hanging in system
docker run --rm -it -v ~/nginx-packages:/opt build-nginx
```

Or you can build container with Dockerfile. For that you should to edit codename for your ubuntu release in `Dockerfile`:

```bash
ARG BASE_IMAGE="ubuntu:xenial"
# and then:
docker build . -t build-nginx -f Dockerfile
docker run --rm -it -v ~/nginx-packages:/opt build-nginx
```