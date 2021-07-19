#!/bin/bash

. /root/run-cfg.sh

cd /root

set -x

apt source nginx
nginx_src=$(readlink -f $(find . -type d -name 'nginx-*' | head -1))

curl -L -O https://github.com/nbs-system/naxsi/archive/${NAXSI_VERSION}.tar.gz && \
tar xzf ${NAXSI_VERSION}.tar.gz && \
mv naxsi-${NAXSI_VERSION} http-naxsi && \
cp -r http-naxsi ${nginx_src}/debian/modules/

cd ${nginx_src}/debian

echo -e -n "\nPackage: libnginx-mod-http-naxsi\n\
Architecture: any\n\
Depends: \${misc:Depends}, \${shlibs:Depends}\n\
Description: WAF Naxsi\n" >> control

cp rules rules.bak

# All lines between common_configure_flags and %:
cat rules | \
sed '/^common_configure_flags/,/%:/s/.*/#REPLACE/g' | \
sed '0,/#REPLACE/s//#NEW/' | \
sed 's/#REPLACE//' > rules.new

cat rules.new | grep -B 10000 '^#NEW' > rules.new.1
cat rules.new | grep -A 10000 '^#NEW' > rules.new.2

cat rules.new.1 /root/configure_flags.txt rules.new.2 > rules

. /etc/os-release && \
echo -ne "nginx (${NGINX_BUILD_VERSION}+naxsi${NAXSI_VERSION}) ${VERSION_CODENAME}; urgency=medium\n\
\n\
  * Custom build with WAF Naxsi\n\
\n\
 -- Build with Docker image by Pavel Selivanov <selivan.at.github@gmail.com>  $(date +'%a, %d %b %Y %H:%M:%S %z')\n\n" \
> changelog.new && \
mv changelog changelog.old && \
cat changelog.new changelog.old > changelog

echo "load_module modules/ngx_http_naxsi_module.so;" > libnginx-mod.conf/mod-http-naxsi.conf

cat <<EOF > modules/watch/http-naxsi
version=4
opts="dversionmangle=s/v//,filenamemangle=s%(?:.*?)?v?(\d[\d.]*)\.tar\.gz%libnginx-mod-http-naxsi-$1.tar.gz%"
    https://github.com/nbs-system/naxsi/tags
    (?:.*?/)?v?(\d[\d.]*)\.tar\.gz debian debian/ngxmod uupdate http-naxsi
EOF

#cat << EOF > modules/control
cat << EOF >> modules/control

Module: naxsi
Homepage: https://github.com/nbs-system/naxsi
Files-Excluded: .travis.yml
Version: ${NAXSI_VERSION}

EOF

cat << EOF > libnginx-mod-http-naxsi.nginx
#!/usr/bin/perl -w

use File::Basename;

# Guess module name
\$module = basename(\$0, '.nginx');
\$module =~ s/^libnginx-mod-//;

\$modulepath = \$module;
\$modulepath =~ s/-/_/g;

print "mod debian/build-extras/objs/ngx_\${modulepath}_module.so\n";
print "mod debian/libnginx-mod.conf/mod-\${module}.conf\n";

EOF

chmod a+x libnginx-mod-http-naxsi.nginx

cd ..

dpkg-buildpackage -us -uc -b 2>&1 | tee /opt/dpkg-buildpackage.log
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    mv -v ../*.deb /opt
    echo "OK: build successful. Get packages in /opt volume"
else
    echo "ERROR: build failed. Get build logs in /opt volume"
fi
