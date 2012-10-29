#!/bin/bash

# Install:
# - Ruby 1.9 for better multi-threading performance than Ruby 1.8
# - squid for enabling downloads from this instance.
yum -y install ruby19
yum -y install vsftpd
yum -y install squid
yum -y install lighttpd
yum -y install git

# Magic? No! It is for logging console output properly -- including output of this script!
exec > >(tee /var/www/lighttpd/index.html|tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

service lighttpd start

# Use the ephemeral drive as workspace:
chmod 777 /media/ephemeral0
cd /media/ephemeral0

# Configure vsftpd:
mkdir /media/ephemeral0/opacmo_data
echo -e "anonymous_enable=YES\nanon_root=/media/ephemeral0/opacmo_data\nlocal_enable=YES\nwrite_enable=YES\nlocal_umask=022\nanon_upload_enable=YES\nanon_mkdir_write_enable=YES\nconnect_from_port_20=YES\nlisten=YES\npam_service_name=vsftpd\ntcp_wrappers=YES" > /etc/vsftpd/vsftpd.conf
service vsftpd start

# Configure squid:
grep -v -E '^(maximum_object_size|cache_dir)' /etc/squid/squid.conf > squid.conf.tmp
cp squid.conf.tmp /etc/squid/squid.conf
rm -f squid.conf.tmp
echo "maximum_object_size 100000 MB" >> /etc/squid/squid.conf
echo "cache_dir ufs /media/ephemeral0/cache 100000 16 256" >> /etc/squid/squid.conf
mkdir /media/ephemeral0/cache
chmod 777 /media/ephemeral0/cache
/etc/init.d/squid start

# Configure wget to use the squid proxy:
grep -v -E '^((https?|ftp)_proxy|use_proxy)' /etc/wgetrc > wgetrc.tmp
cp wgetrc.tmp /etc/wgetrc
rm -f wgetrc.tmp
echo "https_proxy = http://localhost:3128/" >> /etc/wgetrc
echo "http_proxy = http://localhost:3128/" >> /etc/wgetrc
echo "ftp_proxy = http://localhost:3128/" >> /etc/wgetrc
echo "use_proxy = on" >> /etc/wgetrc

# Get the text-mining pipeline software:
mkdir /media/ephemeral0/pipeline
cd /media/ephemeral0/pipeline
git clone git://github.com/joejimbo/bioknack.git
git clone git://github.com/joejimbo/opacmo.git

# Download PMC OA corpus, dictionaries, ontologies, etc.:
opacmo/make_opacmo.sh freeze | tee -a /media/ephemeral0/pipeline/CACHE_LOG
opacmo/make_opacmo.sh get | tee -a /media/ephemeral0/pipeline/CACHE_LOG

# Signal script completion:
echo "---opacmo---cache-complete---" | tee -a /media/ephemeral0/pipeline/CACHE_LOG

# And now, wait forever:
cat > /dev/null

