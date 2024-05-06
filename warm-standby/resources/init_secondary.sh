#/bin/bash

# Install Apache, PHP
dnf update -y
dnf install -y httpd wget php-fpm php-mysqli php-json php php-devel
usermod -a -G apache ec2-user
chown -R ec2-user:apache /var/www
chmod 2775 /var/www && find /var/www -type d -exec sudo chmod 2775 {} \;

# Download and install wordpress
wget https://wordpress.org/latest.tar.gz
tar xvfz latest.tar.gz
mv wordpress/* /var/www/html/
rm -rf wordpress latest.tar.gz
chown -R ec2-user:apache /var/www/html
chmod -R 755 /var/www/html

# Configure database connection
standby_database_secret=$(aws ec2 describe-instances   --instance-id $(ec2-metadata -i | cut -d ' ' -f2)   --query "Reservations[*].Instances[*].Tags[?Key=='STANDBY_DATABASE_SECRET'].Value" |jq -r '.[0][0][0]')
region=$(ec2-metadata -z | awk -F ': ' '{print $2}' | sed 's/.$//')
secret_json=$(aws secretsmanager get-secret-value --region $region --secret-id "$standby_database_secret" --query 'SecretString' | sed 's/^"\(.*\)"$/\1/' | sed 's/\\"/"/g')
rds_user=$(echo "$secret_json" | jq -r '.username')
rds_pass=$(echo "$secret_json" | jq -r '.password')
rds_hostname=$(echo "$secret_json" | jq -r '.host')
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i "s/database_name_here/wordpress/g" /var/www/html/wp-config.php
sed -i "s/username_here/$rds_user/g" /var/www/html/wp-config.php
sed -i "s/password_here/$rds_pass/g" /var/www/html/wp-config.php
sed -i "s/localhost/$rds_hostname/g" /var/www/html/wp-config.php

# Mount EFS
efs_id=$(aws ec2 describe-instances   --instance-id $(ec2-metadata -i | cut -d ' ' -f2)   --query "Reservations[*].Instances[*].Tags[?Key=='STANDBY_EFS_ID'].Value" |jq -r '.[0][0][0]')
mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $efs_id.efs.$region.amazonaws.com:/ /var/www/html/wp-content

# Start httpd
systemctl start httpd