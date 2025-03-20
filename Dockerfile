ARG BASE_IMAGE="ubuntu:24.04"
FROM ${BASE_IMAGE}

LABEL description="Image to build Ubuntu packages of Nginx with custom modules, like Naxsi WAF and GeoIP2(new MaxMind geoip data format)"
LABEL maintainer="Pavel Selivanov(https://github.com/selivan)"

ARG NGINX_VERSION="1.26.3"
ENV NGINX_VERSION=${NGINX_VERSION}

ARG NGINX_CC_OPT=""
ENV NGINX_CC_OPT=${NGINX_CC_OPT}
# -fdebug-prefix-map=./nginx-1.24.0=/usr/src/nginx-1.24.0-2ubuntu7.1
# -ffile-prefix-map=./nginx=.
ENV NGINX_BUILD_ARGS="--with-cc-opt='${NGINX_CC_OPT} -g -O2 -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -flto=auto -ffat-lto-objects -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fcf-protection -fPIC -Wdate-time -D_FORTIFY_SOURCE=3' --with-ld-opt='-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -Wl,-z,relro -Wl,-z,now -fPIC' --prefix=/usr/share/nginx --conf-path=/etc/nginx/nginx.conf --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log --lock-path=/var/lock/nginx.lock --pid-path=/run/nginx.pid --modules-path=/usr/lib/nginx/modules --http-client-body-temp-path=/var/lib/nginx/body --http-fastcgi-temp-path=/var/lib/nginx/fastcgi --http-proxy-temp-path=/var/lib/nginx/proxy --http-scgi-temp-path=/var/lib/nginx/scgi --http-uwsgi-temp-path=/var/lib/nginx/uwsgi --with-compat --with-debug --with-pcre-jit --with-http_ssl_module --with-http_stub_status_module --with-http_realip_module --with-http_auth_request_module --with-http_v2_module --with-http_slice_module --with-threads --with-http_addition_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_random_index_module --with-http_secure_link_module --with-http_sub_module --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module --with-stream=dynamic --sbin-path=/usr/sbin/nginx"

ENV DEBIAN_FRONTEND=noninteractive
# This is required to install tzdata package without questions
ENV TZ=Etc/UTC

ENV ADD_PACKAGES="curl ca-certificates atool autoconf jq yq checkinstall libssl-dev zlib1g-dev libpcre3-dev"

RUN sed -i 's/Types: deb/Types: deb deb-src/g' /etc/apt/sources.list.d/ubuntu.sources && \
    apt update && \
    apt dist-upgrade --yes && \
    apt install --yes --install-recommends=no $ADD_PACKAGES && \
    apt build-dep --yes --install-recommends=no nginx
VOLUME [ "/opt" ]

WORKDIR /opt
ENTRYPOINT ["/opt/run.sh"]
