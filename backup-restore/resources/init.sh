#/bin/bash

# Install Apache, PHP, MariaDB
dnf update -y
dnf install -y httpd wget php-fpm php-mysqli php-json php php-devel mariadb105-server
systemctl start mariadb httpd
systemctl enable mariadb httpd
usermod -a -G apache ec2-user
chown -R ec2-user:apache /var/www
chmod 2775 /var/www && find /var/www -type d -exec sudo chmod 2775 {} \;

# Prepare database for wordpress
MYSQL_WP_PASSWORD="$(openssl rand -base64 12)"
mysql -uroot -e "CREATE USER 'wordpress-user'@'localhost' IDENTIFIED BY '$MYSQL_WP_PASSWORD';"
mysql -uroot -e "CREATE DATABASE wordpress; GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress-user'@'localhost'; FLUSH PRIVILEGES;"

# Download and install wordpress
wget https://wordpress.org/latest.tar.gz
tar xvfz latest.tar.gz
mv wordpress/* /var/www/html/
rm -rf wordpress latest.tar.gz
chown -R ec2-user:apache /var/www/html
chmod -R 755 /var/www/html

# Configure wordpress
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i "s/database_name_here/wordpress/g" /var/www/html/wp-config.php
sed -i "s/username_here/wordpress-user/g" /var/www/html/wp-config.php
sed -i "s/password_here/$MYSQL_WP_PASSWORD/g" /var/www/html/wp-config.php # for demonstration purposes only. We recommend to use a password vault / secrets manager in production.

# Install wp-cli
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# Configure WP site
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` 
PUBLIC_HOSTNAME=`curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/public-hostname`
WP_ADMIN_PASSWORD="$(openssl rand -base64 12)"
echo $WP_ADMIN_PASSWORD > /root/admin_password.txt
wp core install \
        --allow-root \
        --path=/var/www/html \
		--url=${PUBLIC_HOSTNAME} \
		--title=DemoPage \
		--admin_user=admin \
		--admin_password=${WP_ADMIN_PASSWORD}\
		--admin_email=admin@localhost.local

# Download and copy sample data
cpg_folder="/var/www/html/wp-content/cpg"
aws s3 cp --recursive --no-sign-request s3://cellpainting-gallery/cpg0003-rosetta/ $cpg_folder
for ((i=1; i<=11; i++)); do
    destination_folder="${cpg_folder}$(printf "%02d" $i)"
    cp -r --reflink=never "$cpg_folder" "$destination_folder"
done
