#!/bin/bash

sed_regexp=-E

# Journal prefixes for the worker spot-instances that will be started (on top of the one "cache" spot-instance):
WORKERS=(A C E)

# AWS EC2 AMI to use:
ami=ami-1624987f

# AWS EC2 instance type:
instance_type=m1.xlarge

# AWS EC2 zone in which the instances will be created:
zone=us-east-1a

# Number of seconds to wait between checks whether the "cache" spot-instance is up:
SPOT_CHECK_INTERVAL=30

# Number of seconds to wait between checks whether the "cache" spot-instance is done downloading:
CACHE_CHECK_INTERVAL=120

# Determine suitable price:
N=0
FACTOR=1.5
AVG_PRICE=0.0
ec2-describe-spot-price-history -t $instance_type --product-description 'Linux/UNIX' | cut -f 2 -d '	' | sort -n > tmp/aws_prices.tmp
for price in ` cat tmp/aws_prices.tmp` ; do
	AVG_PRICE=`echo "$AVG_PRICE+$price" | bc`
	let N=N+1
done
MEDIAN_PRICE=`awk '{ count[NR] = $1; } END { if (NR % 2) { print count[(NR + 1) / 2]; } else { print (count[(NR / 2)] + count[(NR / 2) + 1]) / 2.0; } }' tmp/aws_prices.tmp`
MEDIAN_PRICE=`echo "scale=3;$MEDIAN_PRICE/1" | bc | sed $sed_regexp 's/^\./0./'`
AVG_PRICE=`echo "scale=3;$AVG_PRICE/$N" | bc | sed $sed_regexp 's/^\./0./'`
MAX_PRICE=`echo "scale=3;$MEDIAN_PRICE*$FACTOR" | bc | sed $sed_regexp 's/^\./0./'`
rm -f tmp/aws_prices.tmp

echo "Over $N reported prices, all zones (via 'ec2-describe-spot-price-history'):"
echo "Average price: $AVG_PRICE"
echo "Median price: $MEDIAN_PRICE"
echo ""
echo "Suggest max. price for opacmo run: $MAX_PRICE (${FACTOR}x median price)"

echo -n "Type 'yes' (without the quotes) to accept: "
read user_agreement

if [ "$user_agreement" != 'yes' ] ; then
	echo 'You declined the suggested price. Aborting.'
	exit 1
fi

TIMESTAMP=`date +%Y%m%d_%H%M`
echo "Setting up 'opacmo_$TIMESTAMP' security group..."
SECURITY_GROUP=`ec2-create-group --description 'opacmo security group' opacmo_$TIMESTAMP | cut -f 2 -d '	'`
if [ "$SECURITY_GROUP" = '' ] ; then
	echo "Could not create the security group 'opacmo' (via ec2-create-group). Does it already exist?"
	exit 2
fi
echo "Security group 'opacmo_$TIMESTAMP' created: $SECURITY_GROUP"
ec2-authorize $SECURITY_GROUP -p 22
ec2-authorize $SECURITY_GROUP -o $SECURITY_GROUP -u $AWS_ACCOUNT_ID

echo "Requesting spot instance (via ec2-request-spot-instances)..."
SPOT_INSTANCE_REQUEST=`ec2-request-spot-instances -g opacmo_$TIMESTAMP -p $MAX_PRICE -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file opacmo/ec2/cache.sh $ami | cut -f 2 -d '	'`
echo "Spot instance request filed: $SPOT_INSTANCE_REQUEST"

echo "Waiting for instance to boot..."
INSTANCE=
while [ "$INSTANCE" = "" ] ; do
	echo "...waiting..."
	sleep $SPOT_CHECK_INTERVAL
	INSTANCE=`ec2-describe-spot-instance-requests $SPOT_INSTANCE_REQUEST | cut -f 12 -d '	'`
done

echo "Instance started: $INSTANCE"

echo "Waiting for instance to download PMC corpus, dictionaries/ontologies, etc."
DOWNLOAD_COMPLETE=0
while [ "$DOWNLOAD_COMPLETE" = "0" ] ; do
	echo "...waiting..."
	sleep $CACHE_CHECK_INTERVAL
	DOWNLOAD_COMPLETE=`ec2-get-console-output $INSTANCE | grep -o 'user-data: ---opacmo---cache-complete---' | wc -l | tr -d ' '`
done

echo "Starting worker instances..."
CACHE_IP=`ec2-describe-addresses | grep "	$INSTANCE	" | cut -f 2 -d '	'`
for prefix in ${WORKERS[@]} ; do
	echo "Starting worker for journal prefix: $prefix"
	sed $sed_regexp "s/PREFIX_VAR/$prefix/g" opacmo/ec2/worker.sh | sed $sed_regexp "s/CACHE_IP_VAR/$CACHE_IP/g" > tmp/worker_$prefix.sh
	ec2-request-spot-instances -g opacmo_$TIMESTAMP -p $MAX_PRICE -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file tmp/worker_$prefix.sh $ami
done

