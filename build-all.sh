#!/bin/sh

set -eu

NGINX_VERSION="${NGINX_VERSION:-1.30.0}"
APT_REPO_RELEASES="${APT_REPO_RELEASES:-22.04 24.04 26.04}"
APT_REPO_ARCHITECTURES="${APT_REPO_ARCHITECTURES:-amd64 arm64}"
APT_REPO_COMPONENTS="${APT_REPO_COMPONENTS:-main oldcpu}"
INSTALL_BINFMT="${INSTALL_BINFMT:-0}"
ADD_RELEASE_FOR_OLD_CPU="${ADD_RELEASE_FOR_OLD_CPU:-0}"

. ./scripts/check-nginx-version.sh
check_nginx_version

case "$ADD_RELEASE_FOR_OLD_CPU" in
    0|1) ;;
    *)
        echo "ADD_RELEASE_FOR_OLD_CPU must be 0 or 1" >&2
        exit 1
        ;;
esac

NGINX_CC_OPT_AMD64_DEFAULT="-march=x86-64-v3"
NGINX_LTO_OPT_AMD64_DEFAULT="-flto=auto -ffat-lto-objects"
NGINX_COMMON_CC_OPT_AMD64_DEFAULT="-g -O2 -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fcf-protection -fPIC -Wdate-time -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -Wno-error=discarded-qualifiers"
NGINX_COMMON_CC_OPT_ARM64_DEFAULT="-g -O2 -fno-omit-frame-pointer -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fPIC -Wdate-time -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -Wno-error=discarded-qualifiers"
NGINX_LD_OPT_DEFAULT="-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -fPIC"

platform_available() {
    platform="$1"

    docker run --rm --platform="$platform" ubuntu:24.04 /bin/true
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
    build_variant="${3:-default}"

    base_image="ubuntu:${ubuntu_release}"
    docker_platform="linux/${docker_arch}"
    image_tag="build-nginx:${ubuntu_release}-${docker_arch}"
    nginx_package_variant=""
    run_tty_args=""

    case "$docker_arch" in
        amd64)
            case "$build_variant" in
                default)
                    nginx_cc_opt="${NGINX_CC_OPT_AMD64:-$NGINX_CC_OPT_AMD64_DEFAULT}"
                    ;;
                oldcpu)
                    nginx_cc_opt=""
                    nginx_package_variant="oldcpu"
                    image_tag="${image_tag}-oldcpu"
                    ;;
                *)
                    echo "Unsupported amd64 build variant: $build_variant" >&2
                    exit 1
                    ;;
            esac
            nginx_lto_opt="${NGINX_LTO_OPT_AMD64:-$NGINX_LTO_OPT_AMD64_DEFAULT}"
            nginx_common_cc_opt="${NGINX_COMMON_CC_OPT_AMD64:-$NGINX_COMMON_CC_OPT_AMD64_DEFAULT}"
            nginx_ld_opt="${NGINX_LD_OPT_AMD64:-$NGINX_LD_OPT_DEFAULT}"
            ;;
        arm64)
            if [ "$build_variant" != "default" ]; then
                echo "Unsupported arm64 build variant: $build_variant" >&2
                exit 1
            fi
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

    echo "==> Building ${base_image} ${docker_platform} nginx ${NGINX_VERSION} (${build_variant})"

    set -- docker build . \
        -t "$image_tag" \
        --platform="$docker_platform" \
        --build-arg BASE_IMAGE="$base_image" \
        --build-arg NGINX_VERSION="$NGINX_VERSION" \
        --build-arg NGINX_CC_OPT="$nginx_cc_opt" \
        --build-arg NGINX_LTO_OPT="$nginx_lto_opt" \
        --build-arg NGINX_COMMON_CC_OPT="$nginx_common_cc_opt" \
        --build-arg NGINX_LD_OPT="$nginx_ld_opt"
    if [ "${http_proxy+x}" = "x" ]; then
        set -- "$@" --build-arg "http_proxy=$http_proxy"
    fi
    if [ "${https_proxy+x}" = "x" ]; then
        set -- "$@" --build-arg "https_proxy=$https_proxy"
    fi
    "$@"

    if [ -t 0 ]; then
        run_tty_args="-it"
    fi

    set -- docker run --rm
    if [ -n "$run_tty_args" ]; then
        set -- "$@" "$run_tty_args"
    fi
    if [ "${http_proxy+x}" = "x" ]; then
        set -- "$@" -e "http_proxy=$http_proxy"
    fi
    if [ "${https_proxy+x}" = "x" ]; then
        set -- "$@" -e "https_proxy=$https_proxy"
    fi
    if [ "${I_REALLY_WANT_TO_BUILD_UNSTABLE:-}" = "1" ]; then
        set -- "$@" -e "I_REALLY_WANT_TO_BUILD_UNSTABLE=1"
    fi
    if [ -n "$nginx_package_variant" ]; then
        set -- "$@" -e "NGINX_PACKAGE_VARIANT=$nginx_package_variant"
    fi
    "$@" \
        --platform="$docker_platform" \
        -e UBUNTU_RELEASE="$ubuntu_release" \
        -e APT_REPO_RELEASES="$APT_REPO_RELEASES" \
        -e APT_REPO_ARCHITECTURES="$APT_REPO_ARCHITECTURES" \
        -e APT_REPO_COMPONENTS="$APT_REPO_COMPONENTS" \
        -v "$(pwd)":/opt \
        "$image_tag"
}

ensure_platform_available linux/amd64
ensure_platform_available linux/arm64

for ubuntu_release in 24.04 22.04 26.04; do
    build_one "$ubuntu_release" amd64
    if [ "$ADD_RELEASE_FOR_OLD_CPU" = "1" ]; then
        build_one "$ubuntu_release" amd64 oldcpu
    fi
    build_one "$ubuntu_release" arm64
done

printf '\033[32mOK: all builds finished. \033[0m Check packages and repo dirs\n'
