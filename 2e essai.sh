sudo -i

apt update && apt upgrade -y

# Installation des dépendances
apt install -y apache2 mariadb-server php php-{apcu,cli,common,curl,gd,imap,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2} libapache2-mod-php php-soap php-cas

# Config apache

cat << EOF > /etc/apache2/sites-available/glpi.conf
<VirtualHost *:80>
    # ServerName glpi.localhost

    DocumentRoot /var/www/glpi/public

    # If you want to place GLPI in a subfolder of your site (e.g. your virtual host is serving multiple applications),
    # you can use an Alias directive. If you do this, the DocumentRoot directive MUST NOT target the GLPI directory itself.
    Alias "/glpi" "/var/www/glpi/public"

    <Directory /var/www/glpi/public>
        Require all granted

        RewriteEngine On

        # Ensure authorization headers are passed to PHP.
        # Some Apache configurations may filter them and break usage of API, CalDAV, ...
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

        # Redirect all requests to GLPI router, unless file exists.
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
</VirtualHost>
EOF

a2ensite glpi.conf
# a2dissite 000-default.conf
a2enmod rewrite
systemctl restart apache2

# Configuration de la base de données
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql mysql
mysql -e "CREATE DATABASE glpi;"
mysql -e "GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost' IDENTIFIED BY 'glpi';"
mysql -e "GRANT SELECT ON mysql.time_zone_name TO 'glpi'@'localhost';"

# Téléchargement et extraction de GLPI
url='https://github.com/glpi-project/glpi/releases/download/10.0.17/glpi-10.0.17.tgz'
wget -qO- $url | tar xz -C /var/www/
# tar -xvzf glpi-10.0.17.tgz


# Création des fichiers de configuration
cat << EOF > /var/www/glpi/inc/downstream.php
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOF

cat << EOF > /etc/glpi/local_define.php
<?php
    define('GLPI_VAR_DIR', '/var/lib/glpi');
    define('GLPI_LOG_DIR', '/var/log/glpi');
EOF

# Configuration des répertoires
mkdir -p /var/log/glpi
mv /var/www/glpi/config/ /etc/glpi/
mv /var/www/glpi/files/ /var/lib/glpi/

# Configuration des permissions
chown -R www-data:www-data /etc/glpi/
chmod -R 770 /etc/glpi/

# Les privilège sont definies ainsi: propriétaire, groupe, autres
# execution: 1, écriture: 2, lecture: 4

chown -R www-data:www-data /var/{log,lib,www}/glpi 
chmod -R 770 /var/{log,lib}/glpi

chmod -R 550 /var/www/glpi
# chmod -R 660 /var/www/glpi/marketplace

# CONFIGURATION php
php_version=$(php --version | sed -n 's/^PHP \([0-9.]*\).*/\1/p')
sed -i 's/^session.cookie_httponly.*$/session.cookie_httponly = 1/' /etc/php/$php_version/apache2/php.ini
systemctl restart apache2