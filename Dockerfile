FROM php:8.2-apache

RUN apt-get update && apt-get install -y \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libzip-dev libicu-dev libpq-dev libxml2-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) pgsql pdo_pgsql gd zip intl soap exif opcache \
    && rm -rf /var/lib/apt/lists/*

RUN { \
    echo 'max_input_vars = 5000'; \
    echo 'memory_limit = 256M'; \
    echo 'upload_max_filesize = 100M'; \
    echo 'post_max_size = 100M'; \
    echo 'display_errors = Off'; \
    echo 'error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT'; \
} > /usr/local/etc/php/conf.d/moodle.ini

RUN echo 'SetEnvIf X-Forwarded-Proto "https" HTTPS=on' >> /etc/apache2/apache2.conf \
    && curl -fSL https://download.moodle.org/download.php/direct/stable405/moodle-latest-405.tgz -o /tmp/moodle.tgz \
    && tar -xzf /tmp/moodle.tgz --strip-components=1 -C /var/www/html/ \
    && rm /tmp/moodle.tgz \
    && mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/html /var/www/moodledata \
    && chmod -R 755 /var/www/html /var/www/moodledata

RUN cat << 'EOF' > /var/www/html/config.php
<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'pgsql';
$CFG->dblibrary = 'native';
$CFG->dbhost    = getenv('PGHOST');
$CFG->dbname    = getenv('PGDATABASE');
$CFG->dbuser    = getenv('PGUSER');
$CFG->dbpass    = getenv('PGPASSWORD');
$CFG->prefix    = 'mdl_';
$CFG->dboptions = array (
  'dbpersist' => 0,
  'dbport' => getenv('PGPORT') ?: 5432,
  'dbsocket' => '',
);

$CFG->wwwroot   = 'https://' . getenv('RAILWAY_PUBLIC_DOMAIN');
$CFG->dataroot  = '/var/www/moodledata';
$CFG->admin     = 'admin';
$CFG->directorypermissions = 0777;
$CFG->sslproxy = true;
$CFG->getremoteaddrconf = 1;

require_once(__DIR__ . '/lib/setup.php');
EOF

RUN chown www-data:www-data /var/www/html/config.php

CMD ["bash", "-c", "php -r '$c = @pg_connect(\"host=\" . getenv(\"PGHOST\") . \" port=\" . (getenv(\"PGPORT\") ?: 5432) . \" dbname=\" . getenv(\"PGDATABASE\") . \" user=\" . getenv(\"PGUSER\") . \" password=\" . getenv(\"PGPASSWORD\")); if ($c) { @pg_query($c, \"DELETE FROM mdl_config WHERE name = \" . chr(39) . \"install_ip\" . chr(39)); }' && apache2-foreground"]
