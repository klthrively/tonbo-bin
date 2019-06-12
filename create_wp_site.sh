#!/bin/sh

##
## Inputs
##

echo "Enter WPEngine site archive folder (e.g. ~/Downloads/site-archive-x-y-z"
read SITE_ARCHIVE_PATH

echo "Enter the full production URL (Example: https://www.alaskandreamcruises.com):"
read PRODUCTION_URL


##
## Calculated
##

PHP_VARS="DB_NAME DB_PASSWORD DB_USER"
for i in $PHP_VARS; do
    echo "GREP_OPTIONS="" grep $i $SITE_ARCHIVE_PATH/wp-config.php"
    PHP_LINE=`GREP_OPTIONS="" grep $i $SITE_ARCHIVE_PATH/wp-config.php`
    declare ${i}=`php -r "$PHP_LINE; echo $i;"`
done

echo "DB_NAME: $DB_NAME"
echo "DB_USER: $DB_USER"
echo "DB_PASSWORD: $DB_PASSWORD"
SITE_SLUG=${DB_NAME/wp_/}
SITE_DOMAIN=`echo $PRODUCTION_URL | awk -F \/ '{l=split($3,a,"."); print (a[l-1]=="com"?a[l-2] OFS:X) a[l-1] OFS a[l]}' OFS="."`
DEV_SITE_PATH=~/dev/dev.$SITE_DOMAIN


## 
## Mysql
##


echo "Setting up mysql scoped credentials. Enter $DB_PASSWORD and hit enter..."
mysql_config_editor set --login-path=$SITE_SLUG --skip-warn --user=$SITE_SLUG --host=localhost --password

echo "Creating mysql database and user..."

echo "drop database if exists $DB_NAME;" | mysql
echo "create database $DB_NAME;" | mysql
echo "drop user if exists $DB_USER@localhost;" | mysql
echo "create user $DB_USER@localhost identified with mysql_native_password by '$DB_PASSWORD';" | mysql
echo "grant all privileges on *.* to $DB_USER@localhost;" | mysql


echo "Creating dev site dir $DEV_SITE_PATH..."
mkdir -p $DEV_SITE_PATH


echo "Copying archive to dev site..."
cp -R $SITE_ARCHIVE_PATH/* $DEV_SITE_PATH


mkdir -p $DEV_SITE_PATH/bin
cat > $DEV_SITE_PATH/bin/restore.sh <<-EOF
 
#!/bin/sh

#
# Setup db on dev:
# - get wp-config from existing site
# - create db with same name
# - replace db name in this script

# requires the following command first:
#
# mysql_config_editor set --login-path=$SITE_SLUG --user=$SITE_SLUG --host=localhost --password
# <enter password: $DB_PASSWORD>
# MYSQL:
#   create database wp_$SITE_SLUG;
#   create user $SITE_SLUG@localhost;
#   alter user $SITE_SLUG@localhost identified with mysql_native_password by '$DB_PASSWORD';
#   grant all privileges on *.* to $SITE_SLUG@localhost;


MYSQL="mysql --login-path=$SITE_SLUG -u $DB_USER -D $DB_NAME"
OLD_HOSTS="https://$SITE_SLUG.wpengine.com http://$SITE_SLUG.wpengine.com $PRODUCTION_URL"
NEW_HOST="http://dev.$SITE_DOMAIN"


##
## Shouldn't have to edit anything below here.
##


echo "Dropping all tables..."
\$MYSQL -e "DROP DATABASE \$DATABASE; create database \$DATABASE"


echo "Pulling in sql dump..."
\$MYSQL < \$1

for OLD_HOST in \$OLD_HOSTS; do
    echo "Fixing entries for "\$OLD_HOST "..."

    \$MYSQL -e "UPDATE wp_options SET option_value = replace(option_value, '\$OLD_HOST', '\$NEW_HOST') WHERE option_name = 'home' OR option_name = 'siteurl';"
    \$MYSQL -e "UPDATE wp_posts SET guid = replace(guid, '\$OLD_HOST','\$NEW_HOST');"
    \$MYSQL -e "UPDATE wp_posts SET post_content = replace(post_content, '\$OLD_HOST', '\$NEW_HOST');"
    \$MYSQL -e "UPDATE wp_postmeta SET meta_value = replace(meta_value,'\$OLD_HOST','\$NEW_HOST');"
done

EOF

chmod +x $DEV_SITE_PATH/bin/restore.sh

echo "Importing WPEngine database dump"
$DEV_SITE_PATH/bin/restore.sh $DEV_SITE_PATH/wp-content/mysql.sql




##
## Nginx
##

echo "Generating nginx config file /usr/local/etc/nginx/sites-available/dev.$SITE_DOMAIN..."

cat > /usr/local/etc/nginx/sites-available/dev.$SITE_DOMAIN <<-EOF
 
server {

    listen                          80;

    # substitute your web server's local URL with yours
    server_name                     dev.$SITE_DOMAIN;

    index                           index.php;
    client_max_body_size            40M;

    access_log 			    /usr/local/var/log/nginx/dev.$SITE_DOMAIN.access.log;
    error_log 			    /usr/local/var/log/nginx/dev.$SITE_DOMAIN.error.log;

    # substitute your web server's root folder with yours
    root			    /Users/kristenlindsey/dev/dev.$SITE_DOMAIN;

    location ~ \\.php\$ {
        try_files                   \$uri =404;
        fastcgi_index               index.php;
        fastcgi_param               SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout        300;
        fastcgi_keep_conn           on;
        include                     /usr/local/etc/nginx/fastcgi_params;
        # include   /usr/local/etc/nginx/conf.d/php-fpm;
        
        # Php-fpm is bound to port 9000
        fastcgi_pass                127.0.0.1:9000;
        index                       index.html index.php;    
    }

    location / {
        try_files                   \$uri
                                    \$uri/
                                    /index.php?\$args;
    }
}

EOF


ln -sf /usr/local/etc/nginx/sites-available/dev.$SITE_DOMAIN /usr/local/etc/nginx/sites-enabled/dev.$SITE_DOMAIN

echo "Restarting nginx...."
brew services restart nginx

echo "Adding entry to /etc/hosts..."
echo "127.0.0.1       dev.$SITE_DOMAIN" | sudo tee -a /etc/hosts

