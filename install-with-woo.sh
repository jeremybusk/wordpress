#!/bin/bash
set -ex
shopt -s expand_aliases

cur_user=$(whoami)
if [[ "${cur_user}" == "root" ]]; then
    alias wp="wp --allow-root"
fi
dbname='wordpress'
dbpass='dbadmin'
dbuser='dbadmin'
hostname='localhost'
wp_directory='/var/www/html/'
wp_admin_user='adminuser'
wp_admin_email='adminuser@example.org'
sitename='Example Site'

tmp_dir=$(mktemp -t -d "wordpress".XXXXXXXXXX) \
    || { echo "Failed to create temp file"; exit 1; }

cd "${tmp_dir}"

sudo apt-get update
sudo apt-get install -y curl
sudo apt-get install -y mariadb-server mariadb-client
sudo apt-get install -y nginx-extras php-fpm

sudo apt-get install -y php php-{fpm,pear,cgi,common,zip,mbstring,net-socket,gd,xml-util,mysql,gettext,bcmath}

curl -s -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
php wp-cli.phar --info
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# sudo rm -f "${wp_directory}"/index.nginx-debian.html
sudo rm -rf "${wp_directory}"/*
sudo mysql -u root <<EOF
DROP DATABASE IF EXISTS ${dbname};
DROP USER IF EXISTS '${dbuser}'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
FLUSH PRIVILEGES;
EOF

wp core download
wp core config --dbname="${dbname}" --dbuser="${dbuser}" --dbpass="${dbpass}"
currentdirectory=${PWD##*/}
echo "${currentdirectory}"
wp_admin_password=$(LC_CTYPE=C tr -dc A-Za-z0-9_\!\@\#\$\&\*\(\)-+= < /dev/urandom | head -c 12)
wp db create
wp core install --url="https://localhost" --title="${sitename}" --admin_user="${wp_admin_user}" --admin_password="${wp_admin_password}" --admin_email="${wp_admin_email}"
wp theme install twentysixteen --activate
wp plugin install woocommerce --activate

sudo cp -rp "${tmp_dir}"/* "${wp_directory}/" 
sudo chown -R www-data:www-data "${wp_directory}"

echo "================================================================="
echo "Installation complete. Login with below."
echo "================================================================="
echo "Url: https://${hostname}"
echo "Username: ${wp_admin_user}"
echo "Password: ${wp_admin_password}"
echo "================================================================="

# update wp_options set option_value='https://example.org' where option_id=1 or option_id=2;

cp /etc/nginx/sites-availabled/default /etc/nginx/sites-availabled/default.bkp
cat >/etc/nginx/sites-availabled/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    if ($scheme != "https") {
        return 301 https://$host$request_uri;
    }

    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_certificate /etc/ssl/certs/selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/selfsigned.key;

    index index.php index.html index.htm index.nginx-debian.html;
    server_name _;
    root /var/www/html;

    location / {
        client_max_body_size 50m;
        try_files $uri $uri/ /index.php$is_args$args;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php7.2-fpm.sock;
        }
}
EOF

# Enable https
sudo apt-get install -y python-certbot-nginx
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/selfsigned.key -out /etc/ssl/certs/selfsigned.crt -subj "/C=US/ST=Utah/L=Provo/O=Pyrofex Corp/OU=CI/CN=example.org"
sudo certbot
