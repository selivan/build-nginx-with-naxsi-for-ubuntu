ARG BASE_IMAGE="ubuntu:focal"

FROM ${BASE_IMAGE}

ARG NGINX_PPA="ppa:ondrej/nginx"

ARG NAXSI_VERSION="1.4"
ENV NAXSI_VERSION=$NAXSI_VERSION

ARG IP2LOCATION_LIB_VERSION="8.5.1"
ENV IP2LOCATION_LIB_VERSION=$IP2LOCATION_LIB_VERSION

LABEL description="Image to build Ubuntu packages of Nginx with Naxsi WAF and IP2Location GeoIP"
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
RUN chmod a+rx /root/run.sh
# && \
#     echo "NAXSI_VERSION=${NAXSI_VERSION}" >> /root/run-cfg.sh && \
#     echo "IP2LOCATION_LIB_VERSION=${IP2LOCATION_LIB_VERSION}" >> /root/run-cfg.sh

WORKDIR /root
ENTRYPOINT ["/root/run.sh"]
