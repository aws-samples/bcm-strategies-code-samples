#/bin/bash

# Install Apache, PHP, MariaDB
dnf update -y
dnf install -y httpd wget php-fpm php-mysqli php-json php php-devel mariadb105-server
systemctl start mariadb httpd
systemctl enable mariadb httpd
usermod -a -G apache ec2-user
chown -R ec2-user:apache /var/www
chmod 2775 /var/www && find /var/www -type d -exec sudo chmod 2775 {} \;

# Configure MariaDB for replication
mariadb_config=$(cat <<EOF
[server]
[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mariadb/mariadb.log
pid-file=/run/mariadb/mariadb.pid
[galera]
[embedded]
[mariadb-10.5]
[mariadb]
log-bin
server_id=1
log-basename=master1
binlog-format=mixed
EOF
)
rm -f /etc/my.cnf.d/mariadb-server.cnf
echo "${mariadb_config}" > /etc/my.cnf.d/mariadb-server.cnf
systemctl restart mariadb

mysql_commands=$(cat <<EOF
CREATE USER 'replicator'@'%' IDENTIFIED BY 'replicator';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
FLUSH TABLES WITH READ LOCK;
SET GLOBAL read_only = ON;
SHOW MASTER STATUS;
EOF
)
mysql_output=$(mysql -uroot -e"${mysql_commands}" --batch --skip-column-names)
binlog_name=$(echo "${mysql_output}" | awk '{print $1}')
binlog_position=$(echo "${mysql_output}" | awk '{print $2}')

mysql_commands=$(cat <<EOF
SET GLOBAL read_only = OFF;
UNLOCK TABLES;
EOF
)
mysql -uroot -e"${mysql_commands}" --batch

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

# Configure NFS and export wp-content
systemctl enable nfs-server
systemctl start nfs-server
export_directory="/var/www/html/wp-content"
echo "$export_directory *(rw,sync,no_root_squash)" | tee -a /etc/exports
exportfs -a

# Get Standby Region & Filesystem
standby_region=$(aws ec2 describe-instances   --instance-id $(ec2-metadata -i | cut -d ' ' -f2)   --query "Reservations[*].Instances[*].Tags[?Key=='STANDBY_REGION'].Value" |jq -r '.[0][0][0]')
standby_fs=$(aws ec2 describe-instances   --instance-id $(ec2-metadata -i | cut -d ' ' -f2)   --query "Reservations[*].Instances[*].Tags[?Key=='STANDBY_FILESYSTEM'].Value" |jq -r '.[0][0][0]')

# Configure DataSync
instance_name="WSPrimaryRegionStack/DataSyncInstance" # change this if you change the stack- or instance-name
instance_id=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$instance_name" "Name=instance-state-name,Values=running"  \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output json | jq -r '. // empty')
internal_ip=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query "Reservations[0].Instances[0].PrivateIpAddress" \
    --output json | jq -r '. // empty')
activation_key=$(curl -vvv -G --data-urlencode "activationRegion=$standby_region"   "http://$internal_ip/" 2>&1 | grep -o 'activationKey=[^&]*' | awk -F= '{print $2}')
agent_arn=$(aws datasync create-agent --region $standby_region --activation-key="${activation_key//[^a-zA-Z0-9\-]/}" | jq -r '.AgentArn')

# Create DataSync Location
source_location_arn=$(aws datasync create-location-nfs --region $standby_region --subdirectory "/var/www/html/wp-content" --server-hostname "$(hostname)" --on-prem-config AgentArns=$agent_arn | jq -r '.LocationArn')

# Get DataSync Destination Location
destination_location_arn=$(aws datasync list-locations --region $standby_region | jq -r ".Locations[] | select(.LocationUri | contains(\"$standby_fs\")) | .LocationArn" | head -n 1)

# Create DataSync Task with hourly schedule
aws datasync create-task \
--region $standby_region \
--source-location-arn $source_location_arn \
--destination-location-arn $destination_location_arn \
--schedule ScheduleExpression="rate(1 hour)"

# Allow Ingress on Standby DB Security Group
standby_database=$(aws ec2 describe-instances   --instance-id $(ec2-metadata -i | cut -d ' ' -f2)   --query "Reservations[*].Instances[*].Tags[?Key=='STANDBY_DATABASE'].Value" |jq -r '.[0][0][0]')
standby_database_sg=$(aws ec2 describe-security-groups --query 'SecurityGroups[?Tags[?Key==`STANDBY_RDS_SECURITYGROUP`]].GroupId' --output text --region $standby_region)
public_ip=$(ec2-metadata -v | cut -d ' ' -f2)
aws ec2 authorize-security-group-ingress --group-id $standby_database_sg --protocol tcp --port 3306 --cidr $public_ip/32 --region $standby_region

# Allow Ingress on Primary Instance Security Group
local_sg=$(aws ec2 describe-instances --instance-id $(ec2-metadata -i | cut -d ' ' -f2) --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text)
standby_database_ip=$(nslookup $standby_database | awk '/^Address: / { print $2 }')
aws ec2 authorize-security-group-ingress --group-id $local_sg --protocol tcp --port 3306 --cidr $standby_database_ip/32

# Connect to RDS and start replication
standby_database_secret=$(aws ec2 describe-instances   --instance-id $(ec2-metadata -i | cut -d ' ' -f2)   --query "Reservations[*].Instances[*].Tags[?Key=='STANDBY_DATABASE_SECRET'].Value" |jq -r '.[0][0][0]')
secret_json=$(aws secretsmanager get-secret-value --region $standby_region --secret-id "$standby_database_secret" --query 'SecretString' | sed 's/^"\(.*\)"$/\1/' | sed 's/\\"/"/g')
rds_user=$(echo "$secret_json" | jq -r '.username')
rds_pass=$(echo "$secret_json" | jq -r '.password')
command="call mysql.rds_set_external_master ('$public_ip', 3306, 'replicator', 'replicator', '$binlog_name', $binlog_position, 0);"
mysql -u"${rds_user}" -p"${rds_pass}" -h"${standby_database}" -e"${command}"
command="call mysql.rds_start_replication;"
mysql -u"${rds_user}" -p"${rds_pass}" -h"${standby_database}" -e"${command}"