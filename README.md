# nginx-naxsi-build

Dockerfile to build Ubuntu packages of [Nginx](https://nginx.org/) web server with [Naxsi](https://github.com/nbs-system/naxsi) WAF(Web Application Firewall).

It uses nginx packages from [Ubuntu nginx ppa](https://launchpad.net/~nginx/+archive/ubuntu/stable) as a template and builds `nginx-light` package with naxsi support and couple of other modules(see `run.sh`). Custom packages are set to have version much larger than nginx version(like 101.16 instead of 1.16, see `Dockerfile`) so they always have preference on system with nginx ppa enabled.

Debian nginx build system is quite intricate, and this solution is ugly and lazily made, but it works and produces Debian-like Nginx packages with NAxsi support.

## Usage

docker build . -t build-nginx
docker run -it -v ~/nginx-packages:/opt build-nginx
