#!/bin/bash

# Worker prefix:
prefix=PREFIX_VAR

# Use the ephemeral drive as workspace:
cd /media/ephemeral0

# Install:
# - Ruby 1.9 for better multi-threading performance than Ruby 1.8
yum -y install ruby19
yum -y install lighttpd
yum -y install ftp
yum -y install git

# Magic? No! It is for logging console output properly -- including output of this script!
exec > >(tee /var/www/lighttpd/log.txt|tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

service lighttpd start

# Configure wget to use the squid proxy:
grep -v -E '^((https?|ftp)_proxy|use_proxy)' /etc/wgetrc > wgetrc.tmp
cp wgetrc.tmp /etc/wgetrc
rm -f wgetrc.tmp
echo "https_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "http_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "ftp_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "use_proxy = on" >> /etc/wgetrc

# Get the text-mining pipeline software bundle:
mkdir /media/ephemeral0/pipeline
cd /media/ephemeral0/pipeline
wget http://CACHE_IP_VAR/bundle.tar
tar xf bundle.tar

# Download PMC OA corpus, dictionaries, ontologies, etc., but don't produce labels ("cache" does that):
opacmo/make_opacmo.sh freeze "${prefix}*" | tee -a /media/ephemeral0/pipeline/WORKER_${prefix}_LOG
opacmo/make_opacmo.sh get "${prefix}*" | tee -a /media/ephemeral0/pipeline/WORKER_${prefix}_LOG
opacmo/make_opacmo.sh dictionaries "${prefix}*" | tee -a /media/ephemeral0/pipeline/WORKER_${prefix}_LOG
opacmo/make_opacmo.sh pner "${prefix}*" | tee -a /media/ephemeral0/pipeline/WORKER_${prefix}_LOG
opacmo/make_opacmo.sh tsv "${prefix}*" | tee -a /media/ephemeral0/pipeline/WORKER_${prefix}_LOG

# Package logs and results into separate tar files:
tar cf worker_log_${prefix}.tar fork_*/FORK_LOG VERSION_* WORKER_*
tar cf worker_opacmo_data_${prefix}.tar opacmo_data

# Compress the tar files:
gzip worker_log_${prefix}.tar
gzip worker_opacmo_data_${prefix}.tar

# Uploads the packaged logs/results to the "cache" spot-instance:
ftp -n -v CACHE_IP_VAR << EOT
user anonymous x@y.z
prompt
cd uploads
binary
put worker_log_${prefix}.tar.gz
put worker_opacmo_data_${prefix}.tar.gz
bye
bye
EOT

# Signal script completion:
echo "---opacmo---worker-complete---(${prefix})---"

# And now, terminate the instance:
halt

