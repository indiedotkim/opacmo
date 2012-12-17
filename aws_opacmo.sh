#!/bin/bash

os=`uname`

if [ "$os" != 'Darwin' ] && [ "$os" != 'Linux' ] ; then
	echo "Sorry, but you have to run this script under Mac OS X or Linux."
	exit 1
fi

# Use 'gawk' as default. Mac OS X's 'awk' works as well, but
# for consistency I would suggest running `sudo port install gawk`.
# The default Linux 'awk' does *not* work.
if [ "$os" = 'Darwin' ] ; then
	awk_interpreter=awk
	sed_regexp=-E
fi
if [ "$os" = 'Linux' ] ; then
	awk_interpreter=gawk
	sed_regexp=-r
fi

# Journal prefixes for the worker spot-instances that will be started (on top of the one "cache" spot-instance):
#WORKERS=(A BM B[^M])
# Note: Based on PMC download from 2012-10-31: approx. 105,000 .nxml files per worker
WORKERS=([JNQWXZ] [BKLSU] P [AFGIOY] [CDEHMRTV])

# AWS EC2 AMI to use:
ami=ami-1624987f

# AWS EC2 instance type:
instance_type=m2.2xlarge

# AWS EC2 zone in which the instances will be created:
# Note that availability zones are different for each account, which means that
# picking a fixed zone here does not imply that the same physical zone is used
# across different user accounts.
# (see http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html)
zone=us-east-1a

# Number of seconds to wait between checks whether the "cache" spot-instance is up:
SPOT_CHECK_INTERVAL=30

# Number of seconds to wait between checks whether the "cache" spot-instance's interfaces have IPs yet:
IP_WAIT=5

# Number of seconds to wait between checks whether the "cache" spot-instance is setup and done downloading:
CACHE_SETUP_INTERVAL=10
CACHE_CHECK_INTERVAL=120

# This function looks for a given phrase (param 1) to occur in the log-file
# of the cache instance. If it does not occur, wait a number of seconds (param 2)
# and then re-check.
wait_for_completion() {
	COMPLETE=0
	while [ "$COMPLETE" = "0" ] ; do
		echo -n '.'
		sleep $2
		COMPLETE=`wget -q -O - http://$PUBLIC_CACHE_IP/log.txt | grep -o $1 | wc -l | tr -d ' '`
	done
	echo ''
}

help_message() {
	echo "Usage: aws_opacmo.sh instance_type"
	echo ""
	echo "Note: avoid using this script on its own. Use make_opacmo.sh instead."
	echo ""
	echo "Options for 'instance_type':"
	echo "  ondemand : use on-demand instances (fixed price, guaranteed availability once started)"
	echo "  spot     : use spot instances (variable price, availability not guaranteed)"
}

if [[ ! $# -eq 1 ]] ; then
	help_message
	exit 2
fi

if [ "$1" != 'ondemand' ] && [ "$1" != 'spot' ] ; then
	help_message
	exit 2
fi

pricing=$1

# Create a tmp directory, if it not already exists. This will be used to store
# transient data, s.a. AWS pricing and computer generated scripts that are executed
# on the "worker" instances:
if [ ! -d tmp ] ; then
	mkdir tmp
fi

if [ "$pricing" = 'spot' ] ; then
	# Determine suitable price:
	N=0
	FACTOR=1.5
	AVG_PRICE=0.0
	ec2-describe-spot-price-history -t $instance_type --product-description 'Linux/UNIX' | cut -f 2 -d '	' | sort -n > tmp/aws_prices.tmp
	for price in ` cat tmp/aws_prices.tmp` ; do
		AVG_PRICE=`echo "$AVG_PRICE+$price" | bc`
		let N=N+1
	done
	MEDIAN_PRICE=`$awk_interpreter '{ count[NR] = $1; } END { if (NR % 2) { print count[(NR + 1) / 2]; } else { print (count[(NR / 2)] + count[(NR / 2) + 1]) / 2.0; } }' tmp/aws_prices.tmp`
	MEDIAN_PRICE=`echo "scale=3;$MEDIAN_PRICE/1" | bc | sed $sed_regexp 's/^\./0./'`
	AVG_PRICE=`echo "scale=3;$AVG_PRICE/$N" | bc | sed $sed_regexp 's/^\./0./'`
	MAX_PRICE=`echo "scale=3;$MEDIAN_PRICE*$FACTOR" | bc | sed $sed_regexp 's/^\./0./'`
	rm -f tmp/aws_prices.tmp

	echo "Over $N reported prices, all zones (via 'ec2-describe-spot-price-history'):"
	echo "Average price: $AVG_PRICE"
	echo "Median price: $MEDIAN_PRICE"
	echo ""
	echo "Suggest max. price for opacmo run: $MAX_PRICE (${FACTOR}x median price)"

	echo -n "Type 'yes' (without the quotes) to accept, or enter a max. price (e.g., 0.70): "
	read user_agreement_or_price

	if [ "$user_agreement_or_price" != 'yes' ] ; then
		if [ "`echo -n "$user_agreement_or_price" | grep -o -E '^[0-9]+\.[0-9]+$'`" != "$user_agreement_or_price\n" ] ; then
			MAX_PRICE=$user_agreement_or_price
			echo -n "Type 'yes' to accept your custom price of $MAX_PRICE and continue: "
			read user_agreement
			if [ "$user_agreement" != 'yes' ] ; then
				echo 'You declined your suggested price. Aborting.'
				exit 3
			fi
		else
			echo 'You declined the suggested price. Aborting.'
			exit 4
		fi
	fi
fi

TIMESTAMP=`date +%Y%m%d_%H%M`
echo "Creating 'opacmo_$TIMESTAMP' key pair..."
ec2-create-keypair opacmo_$TIMESTAMP | sed '1d' > opacmo_$TIMESTAMP.pem
chmod 600 opacmo_$TIMESTAMP.pem
export AWS_KEY_PAIR=opacmo_$TIMESTAMP

echo "Setting up 'opacmo_$TIMESTAMP' security group..."
SECURITY_GROUP=`ec2-create-group --description 'opacmo security group' opacmo_$TIMESTAMP | cut -f 2 -d '	'`
if [ "$SECURITY_GROUP" = '' ] ; then
	echo "Could not create the security group 'opacmo' (via ec2-create-group). Does it already exist?"
	exit 5
fi
echo "Security group 'opacmo_$TIMESTAMP' created: $SECURITY_GROUP"
ec2-authorize $SECURITY_GROUP -p 22
ec2-authorize $SECURITY_GROUP -p 80
ec2-authorize $SECURITY_GROUP -o $SECURITY_GROUP -u $AWS_ACCOUNT_ID

if [ "$pricing" = 'spot' ] ; then
	echo "Requesting spot instance (via ec2-request-spot-instances)..."
	SPOT_INSTANCE_REQUEST=`ec2-request-spot-instances -g opacmo_$TIMESTAMP -p $MAX_PRICE -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file opacmo/ec2/cache.sh $ami | grep -E 'sir-.+' | cut -f 2 -d '	'`
	echo "Spot instance request filed: $SPOT_INSTANCE_REQUEST"

	echo -n "Waiting for instance to boot."
	INSTANCE=
	while [ "$INSTANCE" = '' ] ; do
		echo -n '.'
		sleep $SPOT_CHECK_INTERVAL
		INSTANCE=`ec2-describe-spot-instance-requests $SPOT_INSTANCE_REQUEST | cut -f 12 -d '	'`
	done
	echo ''
fi

if [ "$pricing" = 'ondemand' ] ; then
	echo "Requesting on-demand instance (via ec2-run-instances)..."
	INSTANCE=`ec2-run-instances --instance-initiated-shutdown-behavior terminate -g opacmo_$TIMESTAMP -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file opacmo/ec2/cache.sh $ami | tail -n+2 | cut -f 2 -d '	'`
fi

echo "Instance started: $INSTANCE"
echo -n "Getting IP addresses."
PUBLIC_CACHE_IP=
while [ "$PUBLIC_CACHE_IP" = '' -o "$PRIVATE_CACHE_IP" = '' ] ; do
	echo -n '.'
	sleep $IP_WAIT
	PUBLIC_CACHE_IP=`ec2-describe-instances $INSTANCE | grep -E "	$INSTANCE	" | cut -f 17 -d '	'`
	PRIVATE_CACHE_IP=`ec2-describe-instances $INSTANCE | grep -E "	$INSTANCE	" | cut -f 18 -d '	'`
done
echo ''
echo "External IP: $PUBLIC_CACHE_IP"
echo "Internal IP: $PRIVATE_CACHE_IP"

echo -n "Waiting for instance setup completion."
wait_for_completion '\-\-\-opacmo\-\-\-setup\-complete\-\-\-' $CACHE_SETUP_INTERVAL

echo 'Moving opacmo/bioknack bundle to the cache instance...'
tar cf bundle.tar opacmo bioknack
scp -i opacmo_$TIMESTAMP.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no bundle.tar ec2-user@$PUBLIC_CACHE_IP:/var/www/lighttpd
echo "Bundle has been transferred." > bundle_transferred.tmp
scp -i opacmo_$TIMESTAMP.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no bundle_transferred.tmp ec2-user@$PUBLIC_CACHE_IP:/var/www/lighttpd
rm -f bundle.tar bundle_transferred.tmp

echo -n "Waiting for instance to download PMC corpus, dictionaries/ontologies, etc."
wait_for_completion '\-\-\-opacmo\-\-\-cache\-complete\-\-\-' $CACHE_CHECK_INTERVAL

echo "Starting worker instances..."
for prefix in ${WORKERS[@]} ; do
	echo "Starting worker for journal prefix: $prefix"
	sed $sed_regexp "s/PREFIX_VAR/$prefix/g" opacmo/ec2/worker.sh | sed $sed_regexp "s/CACHE_IP_VAR/$PRIVATE_CACHE_IP/g" > tmp/worker_$prefix.sh

	if [ "$pricing" = 'spot' ] ; then
		ec2-request-spot-instances -g opacmo_$TIMESTAMP -p $MAX_PRICE -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file tmp/worker_$prefix.sh $ami
	fi

	if [ "$pricing" = 'ondemand' ] ; then
		ec2-run-instances --instance-initiated-shutdown-behavior terminate -g opacmo_$TIMESTAMP -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file tmp/worker_$prefix.sh $ami
	fi
done

