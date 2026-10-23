#!/bin/sh

check_nginx_version() {
    if ! printf '%s\n' "${NGINX_VERSION:-}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "ERROR: NGINX_VERSION must have the N.N.N format, got: ${NGINX_VERSION:-<empty>}" >&2
        return 1
    fi

    nginx_minor="${NGINX_VERSION#*.}"
    nginx_minor="${nginx_minor%%.*}"
    echo "nginx_minor=$nginx_minor"

    case "$nginx_minor" in
        *[02468]) return 0 ;;
    esac

    if [ "${I_REALLY_WANT_TO_BUILD_UNSTABLE:-}" = "1" ]; then
        return 0
    fi

    if [ ! -t 0 ]; then
        printf '\033[38;5;208m⚠️ NGINX_VERSION=%s is mainline, not stable.\033[0m\n' "$NGINX_VERSION" >&2
        echo "ERROR: interactive confirmation is unavailable; set I_REALLY_WANT_TO_BUILD_UNSTABLE=1 to continue." >&2
        return 1
    fi

    printf '\033[38;5;208m⚠️ NGINX_VERSION=%s is mainline, not stable. Do you really want to build mainline? [Y/n] \033[0m' "$NGINX_VERSION" >&2
    IFS= read -r nginx_mainline_answer || {
        printf '\n' >&2
        return 1
    }

    case "$nginx_mainline_answer" in
        ''|y|Y)
            I_REALLY_WANT_TO_BUILD_UNSTABLE=1
            export I_REALLY_WANT_TO_BUILD_UNSTABLE
            ;;
        *)
            echo "Build cancelled." >&2
            return 1
            ;;
    esac
}
