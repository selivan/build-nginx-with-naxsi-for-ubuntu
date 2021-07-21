ARG BASE_IMAGE="ubuntu:focal"

FROM ${BASE_IMAGE}

ARG NGINX_PPA="ppa:ondrej/nginx"
ARG NAXSI_VERSION="1.3"

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

VOLUME [ "/opt" ]

COPY run*sh /root/
COPY configure_flags.txt /root/
COPY control /root/
RUN chmod a+x /root/run.sh && \
    echo "NAXSI_VERSION=${NAXSI_VERSION}" >> /root/run-cfg.sh

WORKDIR /root
ENTRYPOINT ["/root/run.sh"]
