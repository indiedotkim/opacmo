#!/bin/bash

sed_regexp=-E

# Number of seconds to wait between checks whether the "batcher" spot-instance is up:
SPOT_CHECK_INTERVAL=5

# Determine suitable price:
N=0
FACTOR=1.5
AVG_PRICE=0.0
ec2-describe-spot-price-history -H -t m1.large --product-description 'Linux/UNIX' | tail -n+2 | cut -f 2 -d '	' | sort -n > tmp/aws_prices.tmp
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
echo "Suggest max. price for opacmo run: $MAX_PRICE (${FACTOR}x median)"

echo -n "Type 'yes' (without the quotes) to accept: "
read user_agreement

if [ "$user_agreement" != 'yes' ] ; then
	echo 'You declined the suggested price. Aborting.'
	exit 1
fi

echo "Requesting spot instance (via ec2-request-spot-instances)..."
SPOT_INSTANCE_REQUEST=`ec2-request-spot-instances -g opacmo -p $MAX_PRICE -t m1.large -b '/dev/sda2=ephemeral0' --user-data-file ec2/bundler.sh ami-1624987f | cut -f 2 -d '	'`
echo "Spot instance request filed: $SPOT_INSTANCE_REQUEST"

echo "Waiting for instance to boot..."
INSTANCE=
while [ "$INSTANCE" = "" ] ; do
	echo "...waiting..."
	sleep $SPOT_CHECK_INTERVAL
	INSTANCE=`ec2-describe-spot-instance-requests $SPOT_INSTANCE_REQUEST | cut -f 12 -d '	'`
done

echo "Instance started: $INSTANCE"

ec2-get-console-output $INSTANCE

