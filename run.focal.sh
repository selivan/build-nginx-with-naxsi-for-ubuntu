#!/bin/bash

# . /root/run-cfg.sh

cd /root

set -x

# GET NGINX SOURCE

NGINX_ORIG_VERSION=$(apt-cache policy nginx | grep -A1 'Version table' | grep -v 'Version table' | tr -s ' ' | cut -d' ' -f2 | cut -d'+' -f1)
NGINX_BUILD_VERSION="10$NGINX_ORIG_VERSION"
# NAXSI_CODE_URL_PREFIX="https://github.com/nbs-system/naxsi/archive/"
# NAXSI_CODE_FILENAME="${NAXSI_VERSION}.tar.gz"

# NAXSI_CODE_URL_PREFIX="https://github.com/wargio/naxsi/archive/refs/tags/"
# NAXSI_CODE_FILENAME="${NAXSI_VERSION}.tar.gz"

NAXSI_CODE_URL_PREFIX="https://github.com/wargio/naxsi/releases/download/${NAXSI_VERSION}/"
NAXSI_CODE_FILENAME="naxsi-${NAXSI_VERSION}-src-with-deps.tar.gz"

apt source nginx
nginx_src=$(readlink -f $(find . -type d -name 'nginx-*' | head -1))

# GET LIBRARIES

curl -L -O "${NAXSI_CODE_URL_PREFIX}${NAXSI_CODE_FILENAME}"
mkdir -p http-naxsi
tar -C http-naxsi -xzf "${NAXSI_CODE_FILENAME}"
if test -d http-naxsi/naxsi-${NAXSI_VERSION}; then
    mv http-naxsi/naxsi-${NAXSI_VERSION}/* http-naxsi
fi
cp -r http-naxsi ${nginx_src}/debian/modules/

curl -L -O https://github.com/chrislim2888/IP2Location-C-Library/archive/refs/tags/${IP2LOCATION_LIB_VERSION}.tar.gz
tar xzf ${IP2LOCATION_LIB_VERSION}.tar.gz
mv IP2Location-C-Library-${IP2LOCATION_LIB_VERSION} ip2location-lib

curl -L -O https://github.com/ip2location/ip2location-nginx/archive/master.tar.gz
tar xzf master.tar.gz
# ip2location-nginx-master
cp -r ip2location-nginx-master ${nginx_src}/debian/modules/

# BUILD IP2LOCATION LIBRARY

apt install -y autoconf checkinstall

cd ip2location-lib
autoreconf -i -v --force
# Libraries in /usr/local/lib do not load if referenced just by filename
./configure --prefix=/usr/
make
checkinstall --nodoc --pkgname=libip2location --pkgversion=${IP2LOCATION_LIB_VERSION} --maintainer=root@localhost -y
cp -f libip2location*deb /opt
cd ..

## BUILD NGINX

cd ${nginx_src}/debian

cp control control.bak
cp /root/control control

cp rules rules.bak

# Set FLAVOURS
sed -i 's/^FLAVOURS.*/FLAVOURS := light/' rules

# Set DYN_MODS
sed -i '/^DYN_MODS/,/^$/s/.*/#REPLACE/g' rules
sed -i '0,/#REPLACE/s//#NEW/' rules
sed -i 's/#REPLACE//' rules

cat rules | grep -B 10000 '^#NEW' | grep -v '^#NEW' > rules.new.1
cat rules | grep -A 10000 '^#NEW' | grep -v '^#NEW' > rules.new.2

cat rules.new.1 > rules
cat >> rules <<EOF
DYN_MODS := \\
        http-naxsi \\
        http-ip2location \\
        http-echo \\
        http-geoip2 \\
        http-headers-more-filter \\
        stream \\
        stream-geoip2

override_dh_shlibdeps:
	dh_shlibdeps --dpkg-shlibdeps-params=--ignore-missing-info

EOF
cat rules.new.2 >> rules

# All lines between common_configure_flags and %:
sed -i '/^common_configure_flags/,/^$/s/.*/#REPLACE/g' rules
sed -i '/^light_configure_flags/,/^$/s/.*/#REPLACE/g' rules
sed -i '/^core_configure_flags/,/^$/s/.*/#REPLACE/g' rules
sed -i '/^extras_configure_flags/,/^$/s/.*/#REPLACE/g' rules
sed -i '0,/#REPLACE/s//#NEW/' rules
sed -i 's/#REPLACE//' rules

cat rules | grep -B 10000 '^#NEW' | grep -v '^#NEW' > rules.new.1
cat rules | grep -A 10000 '^#NEW' | grep -v '^#NEW' > rules.new.2

cat rules.new.1 /root/configure_flags.txt rules.new.2 > rules

# Add version to changelog
. /etc/os-release && \
echo -ne "nginx (${NGINX_BUILD_VERSION}+naxsi${NAXSI_VERSION}+ip2location${IP2LOCATION_LIB_VERSION}) ${VERSION_CODENAME}; urgency=medium\n\
\n\
  * Custom build with WAF Naxsi\n\
\n\
 -- Build with Docker image by Pavel Selivanov <selivan.at.github@gmail.com>  $(date +'%a, %d %b %Y %H:%M:%S %z')\n\n" \
> changelog.new && \
mv changelog changelog.old && \
cat changelog.new changelog.old > changelog

echo "load_module modules/ngx_http_naxsi_module.so;" > libnginx-mod.conf/mod-http-naxsi.conf
echo "load_module modules/ngx_http_ip2location_module.so;" > libnginx-mod.conf/mod-http-ip2location.conf

cat << EOF > modules/watch/http-naxsi
version=4
opts="dversionmangle=s/v//,filenamemangle=s%(?:.*?)?v?(\d[\d.]*)\.tar\.gz%libnginx-mod-http-naxsi-$1.tar.gz%"
    https://github.com/nbs-system/naxsi/tags
    (?:.*?/)?v?(\d[\d.]*)\.tar\.gz debian debian/ngxmod uupdate http-naxsi
EOF

# Add naxsi to modules/control
cat << EOF >> modules/control

Module: naxsi
Homepage: https://github.com/nbs-system/naxsi
Files-Excluded: .travis.yml
Version: ${NAXSI_VERSION}

EOF

cat << EOF >> modules/control

Module: ip2location
Homepage: https://github.com/ip2location/ip2location-nginx
Files-Excluded: .travis.yml
Version: ${IP2LOCATION_LIB_VERSION}

EOF

# Magic
cat << EOF > libnginx-mod-http-naxsi.nginx
#!/usr/bin/perl -w

use File::Basename;

# Guess module name
\$module = basename(\$0, '.nginx');
\$module =~ s/^libnginx-mod-//;

\$modulepath = \$module;
\$modulepath =~ s/-/_/g;

print "mod debian/build-light/objs/ngx_\${modulepath}_module.so\n";
print "mod debian/libnginx-mod.conf/mod-\${module}.conf\n";

EOF

chmod a+rx libnginx-mod-http-naxsi.nginx

cat << EOF > libnginx-mod-http-ip2location.nginx
#!/usr/bin/perl -w

use File::Basename;

# Guess module name
\$module = basename(\$0, '.nginx');
\$module =~ s/^libnginx-mod-//;

\$modulepath = \$module;
\$modulepath =~ s/-/_/g;

print "mod debian/build-light/objs/ngx_\${modulepath}_module.so\n";
print "mod debian/libnginx-mod.conf/mod-\${module}.conf\n";

EOF

chmod a+rx libnginx-mod-http-ip2location.nginx

# Fix all *.nginx files - we are building only nginx-light

for i in *.nginx; do

sed -i 's/build-extras/build-light/g' "$i"

done

cd ..

dpkg-buildpackage -us -uc -b 2>&1 | tee /opt/dpkg-buildpackage.log
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    mv -v ../*.deb /opt
    echo "OK: build successful. Get packages in /opt volume"
else
    echo "ERROR: build failed. Get build log dpkg-buildpackage.log in /opt volume"
fi
