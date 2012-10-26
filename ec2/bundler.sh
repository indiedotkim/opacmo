#!/bin/bash

# Magic? No! It is for logging console output properly -- including output of this script!
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Use the ephemeral drive as workspace:
chmod 777 /media/ephemeral0
cd /media/ephemeral0

# Install:
# - Ruby 1.9 for better multi-threading performance than Ruby 1.8
# - squid for enabling downloads from this instance.
# sudo yum install -y git
#yum -y groupinstall 'Development Tools'
#yum -y install readline-devel
yum -y install ruby19
yum -y install squid

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

# Signal script completion:
echo "---opacmo---bundle-complete---"

# And now, wait forever:
cat > /dev/null

