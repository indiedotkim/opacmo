#!/bin/bash

# Install:
# - Ruby 1.9 for better multi-threading performance than Ruby 1.8
# - squid for enabling downloads from this instance.
yum -y install ruby19
yum -y install vsftpd
yum -y install squid
yum -y install lighttpd
yum -y install git

rm /var/www/lighttpd/*
chmod 777 /var/www/lighttpd

# Magic? No! It is for logging console output properly -- including output of this script!
exec > >(tee /var/www/lighttpd/log.txt|tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

service lighttpd start

# Signal that the server is running:
echo "---opacmo---setup-complete---" | tee -a /media/ephemeral0/pipeline/CACHE_LOG

# Use the ephemeral drive as workspace:
cd /media/ephemeral0

# Configure vsftpd:
mkdir /media/ephemeral0/ftp
chmod 755 /media/ephemeral0/ftp
mkdir /media/ephemeral0/ftp/uploads
chmod 777 /media/ephemeral0/ftp/uploads
echo -e "anonymous_enable=YES\nanon_root=/media/ephemeral0/ftp\nlocal_enable=YES\nwrite_enable=YES\nanon_umask=022\nlocal_umask=022\nanon_upload_enable=YES\nanon_mkdir_write_enable=YES\nconnect_from_port_20=YES\nlisten=YES\npam_service_name=vsftpd\ntcp_wrappers=YES" > /etc/vsftpd/vsftpd.conf
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
while [ ! -f '/var/www/lighttpd/bundle_transferred.tmp' ] ; do
	sleep 5
done
tar xf /var/www/lighttpd/bundle.tar

# Download PMC OA corpus, dictionaries, ontologies, etc.:
opacmo/make_opacmo.sh freeze | tee -a /media/ephemeral0/pipeline/CACHE_LOG
opacmo/make_opacmo.sh get | tee -a /media/ephemeral0/pipeline/CACHE_LOG

# Signal script completion:
echo "---opacmo---cache-complete---" | tee -a /media/ephemeral0/pipeline/CACHE_LOG

# Preparing meta-date extraction now:
opacmo/make_opacmo.sh dictionaries | tee -a /media/ephemeral0/pipeline/CACHE_LOG
opacmo/make_opacmo.sh labels | tee -a /media/ephemeral0/pipeline/CACHE_LOG
tar cf cache_labels_${prefix}.tar gene_names.tsv term_names.tsv species_names.tsv titles.tsv journals.tsv year.tsv pmid.tsv doi.tsv
echo "---opacmo---labels-complete---" | tee -a /media/ephemeral0/pipeline/CACHE_LOG

# And now, wait forever:
cat > /dev/null

