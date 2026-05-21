#!/bin/sh

set -eu

NGINX_VERSION="${NGINX_VERSION:-1.30.0}"
APT_REPO_RELEASES="${APT_REPO_RELEASES:-22.04 24.04 26.04}"
APT_REPO_ARCHITECTURES="${APT_REPO_ARCHITECTURES:-amd64 arm64}"
INSTALL_BINFMT="${INSTALL_BINFMT:-0}"

NGINX_CC_OPT_AMD64_DEFAULT=""
NGINX_LTO_OPT_AMD64_DEFAULT="-flto=auto -ffat-lto-objects"
NGINX_COMMON_CC_OPT_AMD64_DEFAULT="-g -O2 -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fcf-protection -fPIC -Wdate-time -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -Wno-error=discarded-qualifiers"
NGINX_COMMON_CC_OPT_ARM64_DEFAULT="-g -O2 -fno-omit-frame-pointer -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fPIC -Wdate-time -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -Wno-error=discarded-qualifiers"
NGINX_LD_OPT_DEFAULT="-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -fPIC"

platform_available() {
    platform="$1"

    docker buildx ls | grep -q "$platform"
}

ensure_platform_available() {
    platform="$1"

    if platform_available "$platform"; then
        return
    fi

    if [ "$INSTALL_BINFMT" = "1" ] && [ "$platform" = "linux/arm64" ]; then
        echo "==> Installing binfmt support for ${platform}"
        docker run --privileged --rm tonistiigi/binfmt --install arm64
        if platform_available "$platform"; then
            return
        fi
    fi

    echo "Docker cannot run ${platform} containers." >&2
    echo "Install binfmt first, or rerun with INSTALL_BINFMT=1 ./build-all.sh" >&2
    exit 1
}

build_one() {
    ubuntu_release="$1"
    docker_arch="$2"

    base_image="ubuntu:${ubuntu_release}"
    docker_platform="linux/${docker_arch}"
    image_tag="build-nginx:${ubuntu_release}-${docker_arch}"
    run_tty_args=""

    case "$docker_arch" in
        amd64)
            nginx_cc_opt="${NGINX_CC_OPT_AMD64:-$NGINX_CC_OPT_AMD64_DEFAULT}"
            nginx_lto_opt="${NGINX_LTO_OPT_AMD64:-$NGINX_LTO_OPT_AMD64_DEFAULT}"
            nginx_common_cc_opt="${NGINX_COMMON_CC_OPT_AMD64:-$NGINX_COMMON_CC_OPT_AMD64_DEFAULT}"
            nginx_ld_opt="${NGINX_LD_OPT_AMD64:-$NGINX_LD_OPT_DEFAULT}"
            ;;
        arm64)
            nginx_cc_opt="${NGINX_CC_OPT_ARM64:-}"
            nginx_lto_opt="${NGINX_LTO_OPT_ARM64:-}"
            nginx_common_cc_opt="${NGINX_COMMON_CC_OPT_ARM64:-$NGINX_COMMON_CC_OPT_ARM64_DEFAULT}"
            nginx_ld_opt="${NGINX_LD_OPT_ARM64:-$NGINX_LD_OPT_DEFAULT}"
            ;;
        *)
            echo "Unsupported architecture: $docker_arch" >&2
            exit 1
            ;;
    esac

    ensure_platform_available "$docker_platform"

    echo "==> Building ${base_image} ${docker_platform} nginx ${NGINX_VERSION}"

    docker build . \
        -t "$image_tag" \
        --platform="$docker_platform" \
        --build-arg BASE_IMAGE="$base_image" \
        --build-arg NGINX_VERSION="$NGINX_VERSION" \
        --build-arg NGINX_CC_OPT="$nginx_cc_opt" \
        --build-arg NGINX_LTO_OPT="$nginx_lto_opt" \
        --build-arg NGINX_COMMON_CC_OPT="$nginx_common_cc_opt" \
        --build-arg NGINX_LD_OPT="$nginx_ld_opt"

    if [ -t 0 ]; then
        run_tty_args="-it"
    fi

    # shellcheck disable=SC2086
    docker run --rm $run_tty_args \
        --platform="$docker_platform" \
        -e UBUNTU_RELEASE="$ubuntu_release" \
        -e APT_REPO_RELEASES="$APT_REPO_RELEASES" \
        -e APT_REPO_ARCHITECTURES="$APT_REPO_ARCHITECTURES" \
        -v "$(pwd)":/opt \
        "$image_tag"
}

for ubuntu_release in 24.04 22.04 26.04; do
    for docker_arch in amd64 arm64; do
        build_one "$ubuntu_release" "$docker_arch"
    done
done

echo "OK: all builds finished. Check packages and repo dirs"
