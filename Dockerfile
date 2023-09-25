FROM php:8.1-apache-buster

ENV ACCEPT_EULA=Y

RUN apt-get update && apt-get install -y apt-transport-https build-essential curl git gnupg2 iputils-ping libaio1 libcurl4-openssl-dev \
    libfreetype6-dev libjpeg62-turbo-dev libonig-dev libpng-dev libpq-dev libxml2-dev libzip-dev nano net-tools \
    traceroute unzip wget zip zlib1g-dev --no-install-recommends \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install prerequisites for the sqlsrv and pdo_sqlsrv PHP extensions.
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && curl https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && apt-get install -y msodbcsql18 mssql-tools18 unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pecl install sqlsrv pdo_sqlsrv

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -sS https://getcomposer.org/installer \
  | php -- --install-dir=/usr/local/bin --filename=composer

# Retrieve the script used to install PHP extensions from the source container.
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/bin/install-php-extensions

# Install required PHP extensions and all their prerequisites available via apt.
RUN chmod uga+x /usr/bin/install-php-extensions && sync && install-php-extensions bcmath curl exif gd imagick intl \
    ldap mbstring mysqli opcache openssl pcntl pdo pdo_odbc pdo_mysql redis soap zip

RUN docker-php-ext-install -j"$(nproc)" iconv \
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd

# ORACLE oci
RUN mkdir /opt/oracle

WORKDIR /opt/oracle

ADD docker-config/instantclient-basic-linux.x64-12.1.0.2.0.zip /opt/oracle
ADD docker-config/instantclient-sdk-linux.x64-12.1.0.2.0.zip /opt/oracle

# Install Oracle Instantclient
RUN unzip /opt/oracle/instantclient-basic-linux.x64-12.1.0.2.0.zip -d /opt/oracle \
    && unzip /opt/oracle/instantclient-sdk-linux.x64-12.1.0.2.0.zip -d /opt/oracle \
    && rm -rf /opt/oracle/*.zip \
    && mv /opt/oracle/instantclient_12_1 /opt/oracle/instantclient \
    && ln -s /opt/oracle/instantclient/libclntsh.so.12.1 /opt/oracle/instantclient/libclntsh.so \
    && ln -s /opt/oracle/instantclient/libocci.so.12.1 /opt/oracle/instantclient/libocci.so

RUN echo /opt/oracle/instantclient/ > /etc/ld.so.conf.d/oic.conf \
    && ldconfig

RUN echo 'export LD_LIBRARY_PATH="/opt/oracle/instantclient"' >> /root/.bashrc \
    && echo 'export ORACLE_BASE="/opt/oracle/instantclient"' >> /root/.bashrc \
    && echo 'export ORACLE_HOME="/opt/oracle/instantclient"' >> /root/.bashrc \
    && echo 'umask 002' >> /root/.bashrc

# Install Oracle extensions
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN echo 'instantclient,/opt/oracle/instantclient/' | pecl install oci8-3.2.1 \
    && docker-php-ext-enable oci8 \
    && docker-php-ext-configure pdo_oci --with-pdo-oci=instantclient,/opt/oracle/instantclient,12.1 \
    && docker-php-ext-install pdo_oci \
    && docker-php-ext-enable sqlsrv pdo_sqlsrv

# Enable Apache Rewrite Module
RUN a2enmod rewrite
RUN a2enmod ssl
RUN a2enmod headers
