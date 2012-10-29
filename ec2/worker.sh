#!/bin/bash

# Worker prefix:
prefix=PREFIX_VAR

# Use the ephemeral drive as workspace:
chmod 777 /media/ephemeral0
cd /media/ephemeral0

# Install:
# - Ruby 1.9 for better multi-threading performance than Ruby 1.8
yum -y install ruby19
yum -y install lighttpd
yum -y install git

# Magic? No! It is for logging console output properly -- including output of this script!
exec > >(tee /var/www/lighttpd/index.html|tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

service lighttpd start

# Configure wget to use the squid proxy:
grep -v -E '^((https?|ftp)_proxy|use_proxy)' /etc/wgetrc > wgetrc.tmp
cp wgetrc.tmp /etc/wgetrc
rm -f wgetrc.tmp
echo "https_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "http_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "ftp_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "use_proxy = on" >> /etc/wgetrc

# Get the text-mining pipeline software:
mkdir /media/ephemeral0/pipeline
cd /media/ephemeral0/pipeline
git clone git://github.com/joejimbo/bioknack.git
git clone git://github.com/joejimbo/opacmo.git

# Download PMC OA corpus, dictionaries, ontologies, etc.:
opacmo/make_opacmo.sh all "${prefix}*" | tee -a /media/ephemeral0/pipeline/WORKER_${prefix}_LOG

echo "put /media/ephemeral0/pipeline/WORKER_${prefix}_LOG" | ftp anonymous@CACHE_IP_VAR

# Signal script completion:
echo "---opacmo---worker-complete---(${prefix})---" | tee -a /media/ephemeral0/pipeline/WORKER_${prefix}_LOG

# And now, wait forever (for now):
cat > /dev/null

