ARG BASE_IMAGE="ubuntu:xenial"

FROM ${BASE_IMAGE}

ARG NGINX_PPA="ppa:nginx/stable"
ARG NAXSI_VERSION="0.56"
ARG NGINX_BUILD_VERSION="101.16"

LABEL description="Image to build Ubuntu packages of Nginx with Naxsi WAF"
LABEL maintainer="Pavel Selivanov(https://github.com/selivan)"

# install apt packages necessary for build
RUN apt update && \
    apt install --install-recommends=no --yes software-properties-common && \
    apt-add-repository --enable-source --yes ${NGINX_PPA} && \
    apt update && \
    apt dist-upgrade --yes && \
    apt build-dep --yes nginx && \
    apt install --yes curl

# DEBUG
#RUN apt install --yes mc vim tmux less

# # download sources
# RUN cd /root && \
#     apt source nginx && \
#     nginx_src=$(find . -type d -name 'nginx-*') && \
#     curl -L -O https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.tar.gz && \
#     tar xzf ${NAXSI_VERSION}.tar.gz && \
#     mv naxsi-${NAXSI_VERSION} http-naxsi && \
#     cp -r http-naxsi ${nginx_src}/debian/modules/

# # patch debian control files to create custom build
# # keep packages:
# # nginx
# # nginx-light
# # libnginx-mod-http-geoip
# # libnginx-mod-http-echo
# # libnginx-mod-http-headers-more-filter
# RUN nginx_src=$(find /root -type d -name 'nginx-*') && \
#     cd ${nginx_src}/debian && \
#     cat control | \
#     sed '/Package: nginx-doc/,/^$/d' | \
#     sed '/Package: nginx-full/,/^$/d' | \
#     sed '/Package: nginx-extras/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-image-filter/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-xslt-filter/,/^$/d' | \
#     sed '/Package: libnginx-mod-mail/,/^$/d' | \
#     sed '/Package: libnginx-mod-stream/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-perl/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-auth-pam/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-lua/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-ndk/,/^$/d' | \
#     sed '/Package: libnginx-mod-nchan/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-upstream-fair/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-cache-purge/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-fancyindex/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-uploadprogress/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-subs-filter/,/^$/d' | \
#     sed '/Package: libnginx-mod-http-dav-ext/,/^$/d' | \
#     sed '/Package: libnginx-mod-rtmp/,/^$/d' | \
#     cat > control.new && \
#     mv control control.bak && \
#     mv control.new control && \
#     echo -n "Package: libnginx-mod-http-naxsi\n\
# Architecture: any\n\
# Depends: \${misc:Depends}, \${shlibs:Depends}\n\
# Description: WAF Naxsi\n" \
#     >> control

# #     perl -pe 's/FLAVOURS := full light extras\n/FLAVOURS := light\n/s' | \
# # DYN_MODULEs: add http_naxsi
# # remove:
# # --with-http_dav_module
# # add:
# # --with-http_geo_module
# # --with-http_limit_req_module
# # --with-http_limit_conn_module
# # add:
# # --add-dynamic-module=$(MODULESDIR)/http-naxsi
# # 
# RUN nginx_src=$(find /root -type d -name 'nginx-*') && \
#     cd ${nginx_src}/debian && \
#     cat rules | \
#     perl -pe 's/DYN_MODS := \\\n/DYN_MODS := \\\nhttp_naxsi \\\n/s' | \
#     perl -pe 's/--with-http_dav_module \\\n//s' | \
#     perl -pe 's/--without-http_geo_module \\\n//s' | \
#     perl -pe 's/--without-http_limit_req_module \\\n//s' | \
#     perl -pe 's/--without-http_limit_conn_module \\\n//s' | \
#     perl -pe 's/--add-dynamic-module=\$\(MODULESDIR\)\/http-echo\\*/--with-http_geoip_module=dynamic \\\n--add-dynamic-module=\$\(MODULESDIR\)\/http-echo \\\n--add-dynamic-module=\$\(MODULESDIR\)\/http-headers-more-filter \\\n--add-dynamic-module=\$\(MODULESDIR\)\/http-naxsi/s' | \
#     perl -pe 's/full_configure_flags.*\n *\n/full_configure_flags := \$\(common_configure_flags\)/s' | \
#     cat > rules.new && \
#     mv rules rules.bak && \
#     mv rules.new rules

# # notice: echo from this /bin/sh version interprets escape sequences
# RUN nginx_src=$(find /root -type d -name 'nginx-*') && \
#     cd ${nginx_src}/debian && \
#     . /etc/os-release && \
#     echo -n "nginx (${NGINX_BUILD_VERSION}) ${VERSION_CODENAME}; urgency=medium\n\
# \n\
#   * Custom build with WAF Naxsi\n\
# \n\
#  -- Build with Docker image by Pavel Selivanov <selivan.at.github@gmail.com>  $(date +'%a, %d %b %Y %H:%M:%S %z')\n\n" \
#     >> changelog.new && \
#     mv changelog changelog.old && \
#     cat changelog.new changelog.old > changelog

# build

VOLUME [ "/opt" ]

ADD run.sh /root/run.sh
RUN chmod a+x /root/run.sh && \
    echo "NAXSI_VERSION=${NAXSI_VERSION}" >> /root/run-cfg.sh && \
    echo "NGINX_BUILD_VERSION=${NGINX_BUILD_VERSION}" >> /root/run-cfg.sh

WORKDIR /root
ENTRYPOINT ["/root/run.sh"]
