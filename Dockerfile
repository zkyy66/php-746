FROM php:7.4.6-fpm
LABEL maintainer="crazy_cat <ages521you@hotmail.com>" version="v1.0"
ARG timezone
ARG app_env=prod
ARG work_user=www-data
ENV APP_ENV=${app_env:-"prod"} \
    TIMEZONE=${timezone:-"Asia/Shanghai"}  \
    NGINX_VERSION=1.17.10 \
    NJS_VERSION=0.3.9 \
    PKG_RELEASE=1~buster \
    PHPREDIS_VERSION=5.2.2 \
    PHPYAF_VERSION=3.2.3 \
    PHP_XDEBUG_V=2.8.0  \
    PHP_PHALXON_VERSION=4.0.6

RUN apt-get clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl wget vim git zip unzip less procps lsof tcpdump htop openssl supervisor zlibc g++ gcc \
        libz-dev \
        libssl-dev \
        libnghttp2-dev \
        libpcre3-dev \
        libjpeg-dev \
        libpng-dev \
        libfreetype6-dev \
        libzip-dev \
        libargon2-dev \
        libcurl4-openssl-dev \
        libedit-dev \
        libonig-dev \
        libsodium-dev \
        libsqlite3-dev \
        libxml2-dev \
        zlib1g-dev \
    && docker-php-ext-install \
        bcmath gd pdo_mysql mbstring sockets zip sysvmsg sysvsem sysvshm
RUN docker-php-ext-enable sodium
##安装composer
RUN curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer \
    && composer self-update --clean-backups
##安装redis扩展
RUN wget http://pecl.php.net/get/redis-${PHPREDIS_VERSION}.tgz -O /tmp/redis.tar.tgz \
    && pecl install /tmp/redis.tar.tgz \
    && rm -rf /tmp/redis.tar.gz \
    && docker-php-ext-enable redis
##安装yaf框架扩展
ADD ext_dir/yaf-${PHPYAF_VERSION}.tgz /tmp
RUN cd /tmp/yaf-${PHPYAF_VERSION} \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && rm -rf /tmp/yaf-* \
    && docker-php-ext-enable yaf
##安装Xdebug框架
ADD ext_dir/xdebug.tar.gz /tmp
RUN cd /tmp/xdebug-${PHP_XDEBUG_V} \
    && ./rebuild.sh \
    && rm -rf /tmp/xdebug.tar.gz \
    && docker-php-ext-enable xdebug
#安装psr
RUN cd /tmp \
    && git clone https://github.com/jbboehr/php-psr.git \
    && cd php-psr \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && docker-php-ext-enable psr 
##安装phalcon
ADD ext_dir/cphalcon-${PHP_PHALXON_VERSION}.tar.gz /tmp
RUN cd /tmp/cphalcon-${PHP_PHALXON_VERSION}/build \
    && ./install \
    && rm -rf /tmp/cphalcon-${PHP_PHALXON_VERSION}.tar.gz \
    && docker-php-ext-enable phalcon
#RUN cd /tmp \
#    && git clone https://github.com/phalcon/cphalcon.git \
#    && cd cphalcon/build \
#    && ./install \
#    && docker-php-ext-enable phalcon
##安装zephir-parser
RUN cd /tmp \
    && git clone git://github.com/phalcon/php-zephir-parser.git \
    && cd php-zephir-parser \
    && phpize \
    && ./configure \
    && make  \
    && make install \
    && rm -rf /tmp/php-* \
    && docker-php-ext-enable zephir_parser
 ##Nginx
ADD ext_dir/nginx-${NGINX_VERSION}.tar.gz /tmp
RUN cd /tmp/nginx-${NGINX_VERSION} \
    && set -x \
    && apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y gnupg1 ca-certificates \
    && \
    NGINX_GPGKEY=573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62; \
    found=''; \
    for server in \
        ha.pool.sks-keyservers.net \
        hkp://keyserver.ubuntu.com:80 \
        hkp://p80.pool.sks-keyservers.net:80 \
        pgp.mit.edu \
    ; do \
        echo "Fetching GPG key $NGINX_GPGKEY from $server"; \
        apt-key adv --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$NGINX_GPGKEY" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch GPG key $NGINX_GPGKEY" && exit 1; \
    apt-get remove --purge --auto-remove -y gnupg1 && rm -rf /var/lib/apt/lists/* \
    && dpkgArch="$(dpkg --print-architecture)" \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-${PKG_RELEASE} \
    " \
    && case "$dpkgArch" in \
        amd64|i386) \
# arches officialy built by upstream
            echo "deb https://nginx.org/packages/mainline/debian/ buster nginx" >> /etc/apt/sources.list.d/nginx.list \
            && apt-get update \
            ;; \
        *) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from the published source packages
            echo "deb-src https://nginx.org/packages/mainline/debian/ buster nginx" >> /etc/apt/sources.list.d/nginx.list \
            \
# new directory for storing sources and .deb files
            && tempDir="$(mktemp -d)" \
            && chmod 777 "$tempDir" \
# (777 to ensure APT's "_apt" user can access it too)
            \
# save list of currently-installed packages so build dependencies can be cleanly removed later
            && savedAptMark="$(apt-mark showmanual)" \
            \
# build .deb files from upstream's source packages (which are verified by apt-get)
            && apt-get update \
            && apt-get build-dep -y $nginxPackages \
            && ( \
                cd "$tempDir" \
                && DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
                    apt-get source --compile $nginxPackages \
            ) \
# we don't remove APT lists here because they get re-downloaded and removed later
            \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
# (which is done after we install the built packages so we don't have to redownload any overlapping dependencies)
            && apt-mark showmanual | xargs apt-mark auto > /dev/null \
            && { [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; } \
            \
# create a temporary local APT repo to install from (so that dependency resolution can be handled by APT, as it should be)
            && ls -lAFh "$tempDir" \
            && ( cd "$tempDir" && dpkg-scanpackages . > Packages ) \
            && grep '^Package: ' "$tempDir/Packages" \
            && echo "deb [ trusted=yes ] file://$tempDir ./" > /etc/apt/sources.list.d/temp.list \
            && apt-get -o Acquire::GzipIndexes=false update \
            ;; \
    esac \
    \
    && apt-get install --no-install-recommends --no-install-suggests -y \
                        $nginxPackages \
                        gettext-base \
                        vim  \
                        wget \
                        curl \
    && apt-get remove --purge --auto-remove -y ca-certificates && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/nginx.list \
    \
    && if [ -n "$tempDir" ]; then \
        apt-get purge -y --auto-remove \
        && rm -rf "$tempDir" /etc/apt/sources.list.d/temp.list; \
    fi
# Clear dev deps
RUN apt-get clean \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
# Timezone
    && cp /usr/share/zoneinfo/${TIMEZONE} /etc/localtime \
    && echo "${TIMEZONE}" > /etc/timezone \
    && echo "[Date]\ndate.timezone=${TIMEZONE}" > /usr/local/etc/php/conf.d/timezone.ini

COPY supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY ext_dir/nginx /etc/nginx
# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

#EXPOSE 9000
EXPOSE 80
##开启扩展 RUN docker-php-ext-enable sodium

STOPSIGNAL SIGTERM
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
HEALTHCHECK --timeout=10s CMD curl --silent --fail http://127.0.0.1:80/fpm-ping

#CMD ["nginx", "-g", "daemon off;"]
#http://127.0.0.1:8888/
