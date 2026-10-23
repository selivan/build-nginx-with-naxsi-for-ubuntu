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
UBUNTU_RELEASE="24.04"
DOCKER_PLATFORM="linux/amd64"
NGINX_VERSION="1.30.4"
NGINX_CC_OPT="-march=x86-64-v3"
docker build . -t build-nginx --platform="$DOCKER_PLATFORM" --build-arg NGINX_VERSION="$NGINX_VERSION" --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg NGINX_CC_OPT="$NGINX_CC_OPT"
# --rm: do not leave the container hanging in system
docker run --rm -it --platform="$DOCKER_PLATFORM" -e UBUNTU_RELEASE="$UBUNTU_RELEASE" -v "$(pwd)":/opt build-nginx
# built packages are now in packages directory
```

The `packages` directory contains the built `.deb` files. The `repo` directory is updated as a signed APT repository:

* `pool/main/n/nginx/*.deb` - optimized amd64 (`x86-64-v3`) and arm64 packages
* `pool/oldcpu/n/nginx/*.deb` - generic amd64 packages for older CPUs
* `dists/<ubuntu-release>/<component>/binary-<arch>/Packages.gz` - package indexes
* `dists/<ubuntu-release>/Release`, `Release.gpg`, `InRelease` - repository metadata and signatures
* `nginx-repo-signing-key.asc` - public signing key to share with users

The private signing keyring is generated in `repo-gpg` and reused by later builds. Keep this directory private.

After manually adding or removing `.deb` files from `repo/pool/`, rebuild and
verify all indexes and signatures without rebuilding nginx packages:

```bash
./scripts/rebuild-nginx-apt-repository.sh
./scripts/verify-nginx-apt-repository.sh
```

Both scripts accept optional `repo` and `repo-gpg` paths as their first two
arguments and honor `APT_REPO_RELEASES`, `APT_REPO_ARCHITECTURES`,
`APT_REPO_COMPONENTS` (or legacy `APT_REPO_COMPONENT`), and related repository environment variables. The
verification rejects mainline nginx packages unless
`I_REALLY_WANT_TO_BUILD_UNSTABLE=1` is explicitly set.

The generated `nginx` package is intended to replace Ubuntu nginx packages. Its Debian metadata declares `Conflicts` and `Replaces` for `nginx-common`, `nginx-core`, `nginx-light`, `nginx-full`, and `nginx-extras`, so switching packages does not fail on shared files.

Package versions include the target Ubuntu release, for example `101.30.0-1~ubuntu24.04`, so one repository can safely contain builds for multiple Ubuntu releases.

For arm64/Graviton builds use Docker platform `linux/arm64` and leave `NGINX_CC_OPT` empty unless you intentionally need CPU-specific compiler flags:

```bash
BASE_IMAGE="ubuntu:24.04"
UBUNTU_RELEASE="24.04"
DOCKER_PLATFORM="linux/arm64"
NGINX_VERSION="1.30.4"
NGINX_CC_OPT=""
NGINX_LTO_OPT=""
docker build . -t build-nginx-arm64 --platform="$DOCKER_PLATFORM" --build-arg NGINX_VERSION="$NGINX_VERSION" --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg NGINX_CC_OPT="$NGINX_CC_OPT" --build-arg NGINX_LTO_OPT="$NGINX_LTO_OPT"
docker run --rm -it --platform="$DOCKER_PLATFORM" -e UBUNTU_RELEASE="$UBUNTU_RELEASE" -v "$(pwd)":/opt build-nginx-arm64
```

To keep metadata for several Ubuntu releases in one repository, pass all releases and architectures when running the build:

```bash
docker run --rm -it \
  --platform="$DOCKER_PLATFORM" \
  -e UBUNTU_RELEASE="$UBUNTU_RELEASE" \
  -e APT_REPO_RELEASES="22.04 24.04 26.04" \
  -e APT_REPO_ARCHITECTURES="amd64 arm64" \
  -v "$(pwd)":/opt \
  build-nginx
```

Run the build once for every target tuple you need, changing `BASE_IMAGE`, `UBUNTU_RELEASE`, `DOCKER_PLATFORM`, and `NGINX_VERSION`. Each run adds its `.deb` to the selected component under `repo/pool/` and regenerates indexes under `repo/dists/`.

Or build the default matrix sequentially for Ubuntu 24.04, 22.04, 26.04 and `amd64`/`arm64`:

```bash
NGINX_VERSION="1.30.4" ./build-all.sh
```

Both Docker platforms are checked before any build starts. If arm64 support is
missing, rerun with `INSTALL_BINFMT=1` to install it through a privileged
`tonistiigi/binfmt` container.

amd64 packages use `-march=x86-64-v3` by default. To additionally build a
generic amd64 package for older CPUs for every Ubuntu release in the matrix:

```bash
ADD_RELEASE_FOR_OLD_CPU=1 NGINX_VERSION="1.30.4" ./build-all.sh
```

This adds packages such as
`nginx_101.30.4-1~ubuntu24.04~oldcpu_amd64.deb` to the `oldcpu` component.
Both components provide the same `nginx` package name.

Use `main` on current CPUs:

```bash
deb http://repo.test.com:80/nginx/repo 24.04 main
```

Use `oldcpu` instead on older amd64 CPUs:

```bash
deb http://repo.test.com:80/nginx/repo 24.04 oldcpu
```

Then install normally with `apt install nginx`. Do not enable both components
on an old CPU: the `main` version has higher APT priority than its `~oldcpu`
counterpart and would be selected by default.

For a direct Docker build, pass an empty `NGINX_CC_OPT` at image build time
and `NGINX_PACKAGE_VARIANT=oldcpu` when running the container.

`NGINX_VERSION` must use the `N.N.N` format. An even minor version, such as
`1.30.x` or `1.32.x`, is treated as stable. An odd minor version is mainline
and requires interactive confirmation before the build starts. For an
intentional non-interactive mainline build, set the explicit override:

```bash
I_REALLY_WANT_TO_BUILD_UNSTABLE=1 NGINX_VERSION="1.31.0" ./build-all.sh
```

When running the container directly, pass the override into it with
`-e I_REALLY_WANT_TO_BUILD_UNSTABLE=1`.

To customize the generated key on the first run:

```bash
docker run --rm -it \
  -e APT_REPO_KEY_NAME="Example nginx packages" \
  -e APT_REPO_KEY_EMAIL="nginx-packages@example.com" \
  -v "$(pwd)":/opt \
  build-nginx
```

To use the repository after publishing `repo/` to a web server:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://example.com/custom_packages/nginx/repo/nginx-repo-signing-key.asc | sudo gpg --dearmor -o /etc/apt/keyrings/custom-nginx.gpg
echo "deb [signed-by=/etc/apt/keyrings/custom-nginx.gpg] https://example.com/custom_packages/nginx/repo 24.04 main" | sudo tee /etc/apt/sources.list.d/custom-nginx.list
sudo apt update
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

The default amd64 Docker build uses:

`--build-arg NGINX_CC_OPT="-march=x86-64-v3"`

Override `NGINX_CC_OPT` with an empty value for generic amd64 or arm64 builds.
`-march=x86-64-v3` requires AVX/AVX2-capable CPUs; on older or constrained
virtualized CPUs the resulting binary can crash with `SIGILL` / `invalid opcode`.

The default LTO flags can be changed with:

`--build-arg NGINX_LTO_OPT="-flto=auto -ffat-lto-objects"`

`build-all.sh` disables `NGINX_LTO_OPT` for arm64 by default because that linker check fails under the arm64 Docker/qemu build path on some hosts.

The common compiler and linker flags can also be overridden when a target architecture needs a different hardening set:

`--build-arg NGINX_COMMON_CC_OPT="-g -O2 -fno-omit-frame-pointer -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fPIC -Wdate-time -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -Wno-error=discarded-qualifiers"`

`--build-arg NGINX_LD_OPT="-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -fPIC"`

Note: you can use command `ld.so --help` (see the end of the output) to detect supported [x86-64 microarchitecture level](https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels) for your hardware.

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
