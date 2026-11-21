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
    && mkdir -p /var/www/moodledata/sessions \
    && chown -R www-data:www-data /var/www/html /var/www/moodledata \
    && chmod -R 777 /var/www/moodledata

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
$CFG->session_handler_class = '\core\session\database';

require_once(__DIR__ . '/lib/setup.php');
EOF

RUN cat << 'EOF' > /usr/local/bin/start-moodle.sh
#!/bin/bash
set -e

mkdir -p /var/www/moodledata/sessions
chown -R www-data:www-data /var/www/moodledata
chmod -R 777 /var/www/moodledata

INSTALLED=$(php -r '
$c = @pg_connect("host=" . getenv("PGHOST") . " port=" . (getenv("PGPORT") ?: 5432) . " dbname=" . getenv("PGDATABASE") . " user=" . getenv("PGUSER") . " password=" . getenv("PGPASSWORD"));
if (!$c) { echo "no_db"; exit; }
$r = @pg_query($c, "SELECT id FROM mdl_user WHERE username = '\''admin'\'' AND email = '\''3d.prints.f0@gmail.com'\''");
echo ($r && pg_num_rows($r) > 0) ? "yes" : "no";
')

echo "Estado actual de Moodle: $INSTALLED"

if [ "$INSTALLED" = "no" ]; then
  echo "Limpiando instalacion incompleta e instalando Moodle 4.5..."
  php -r '
  $c = pg_connect("host=" . getenv("PGHOST") . " port=" . (getenv("PGPORT") ?: 5432) . " dbname=" . getenv("PGDATABASE") . " user=" . getenv("PGUSER") . " password=" . getenv("PGPASSWORD"));
  pg_query($c, "DROP SCHEMA public CASCADE; CREATE SCHEMA public;");
  '
  su -s /bin/bash www-data -c "php /var/www/html/admin/cli/install_database.php --lang=es --adminuser=admin --adminpass='Admin3DPrints#2026' --adminemail='3d.prints.f0@gmail.com' --fullname='3D-Prints' --shortname='3D-Prints' --agree-license"
  echo "Instalacion de Moodle finalizada con exito."
fi

exec apache2-foreground
EOF

RUN chmod +x /usr/local/bin/start-moodle.sh

CMD ["/usr/local/bin/start-moodle.sh"]
