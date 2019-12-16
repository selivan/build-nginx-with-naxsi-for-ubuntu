#!/bin/bash

. /root/run-cfg.sh

cd /root

set -x
apt source nginx
nginx_src=$(find . -type d -name 'nginx-*')

curl -L -O https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.tar.gz && \
tar xzf ${NAXSI_VERSION}.tar.gz && \
mv naxsi-${NAXSI_VERSION} http-naxsi && \
cp -r http-naxsi ${nginx_src}/debian/modules/

cd ${nginx_src}/debian

cat control | \
sed '/Package: nginx-doc/,/^$/d' | \
sed '/Package: nginx-full/,/^$/d' | \
sed '/Package: nginx-extras/,/^$/d' | \
sed '/Package: libnginx-mod-http-image-filter/,/^$/d' | \
sed '/Package: libnginx-mod-http-xslt-filter/,/^$/d' | \
sed '/Package: libnginx-mod-mail/,/^$/d' | \
sed '/Package: libnginx-mod-stream/,/^$/d' | \
sed '/Package: libnginx-mod-http-perl/,/^$/d' | \
sed '/Package: libnginx-mod-http-auth-pam/,/^$/d' | \
sed '/Package: libnginx-mod-http-lua/,/^$/d' | \
sed '/Package: libnginx-mod-http-ndk/,/^$/d' | \
sed '/Package: libnginx-mod-nchan/,/^$/d' | \
sed '/Package: libnginx-mod-http-upstream-fair/,/^$/d' | \
sed '/Package: libnginx-mod-http-cache-purge/,/^$/d' | \
sed '/Package: libnginx-mod-http-fancyindex/,/^$/d' | \
sed '/Package: libnginx-mod-http-uploadprogress/,/^$/d' | \
sed '/Package: libnginx-mod-http-subs-filter/,/^$/d' | \
sed '/Package: libnginx-mod-http-dav-ext/,/^$/d' | \
sed '/Package: libnginx-mod-rtmp/,/^$/d' | \
cat > control.new
mv control control.bak
mv control.new control

echo -e -n "\nPackage: libnginx-mod-http-naxsi\n\
Architecture: any\n\
Depends: \${misc:Depends}, \${shlibs:Depends}\n\
Description: WAF Naxsi\n" >> control

cat rules | \
perl -pe 's/DYN_MODS := \\\n/DYN_MODS := \\\nhttp_naxsi \\\n/s' | \
perl -pe 's/--with-http_dav_module \\\n//s' | \
perl -pe 's/--without-http_geo_module \\\n//s' | \
perl -pe 's/--without-http_limit_req_module \\\n//s' | \
perl -pe 's/--without-http_limit_conn_module \\\n//s' | \
perl -pe 's/--add-dynamic-module=\$\(MODULESDIR\)\/http-echo\\*/--with-http_geoip_module=dynamic \\\n--add-dynamic-module=\$\(MODULESDIR\)\/http-echo \\\n--add-dynamic-module=\$\(MODULESDIR\)\/http-headers-more-filter \\\n--add-dynamic-module=\$\(MODULESDIR\)\/http-naxsi\/naxsi_src/s' | \
perl -pe 's/full_configure_flags.*\n *\n/full_configure_flags := \$\(common_configure_flags\)/s' | \
cat > rules.new
mv rules rules.bak
mv rules.new rules

. /etc/os-release && \
echo -n "nginx (${NGINX_BUILD_VERSION}) ${VERSION_CODENAME}; urgency=medium\n\
\n\
  * Custom build with WAF Naxsi\n\
\n\
 -- Build with Docker image by Pavel Selivanov <selivan.at.github@gmail.com>  $(date +'%a, %d %b %Y %H:%M:%S %z')\n\n" \
>> changelog.new && \
mv changelog changelog.old && \
cat changelog.new changelog.old > changelog

cd ..

dpkg-buildpackage -us -uc -b 2>&1 | tee /opt/dpkg-buildpackage.log
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    mv -v ../*.deb /opt
    echo "OK: build successful. Get packages in /opt volume"
else
    echo "ERROR: build failed. Get build logs in /opt volume"
fi
