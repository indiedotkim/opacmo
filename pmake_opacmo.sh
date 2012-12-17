#!/bin/bash

environment=$1
prefix=$2

# Number of publications that should be grouped together into a batch. A batch
# contains the publications that are processed by a NER task.
batchsize=2000

# Soft limit on maximum number of processes that should be running in parallel.
# Since make_opacmo.sh sets STATE_NER late, there is the possibility that we
# fork more instances than given here just because the 'scheduler' is not aware
# of a freshly spawned process.
if [ "$environment" != 'sge' ] ; then
	max_processes=8
else
	max_processes=100
fi

# Determines the number of cores available on clusters nodes.
# Unless you use Ruby 1.9 or (even better) JRuby, leaving the
# cores set to one is the best option. There will simply be no
# multi-threading in Ruby 1.8.
cores=1

# Memory that should be reserved on cluster nodes.
maxmem=8G

cmd=ner
fork=0

function scheduler() {
	local running=$max_processes
	while [[ $running -ge $max_processes ]] ; do
		running=0
		for forks in fork_* ; do
			if [ -f $forks/STATE_NER ] ; then
				let running=running+1
			fi
		done
		if [[ $running -ge $max_processes ]] ; then sleep 5 ; fi
	done

	return $running
}

if [ ! -d opacmo_data ] ; then mkdir opacmo_data ; fi

# Create batches:
if [ -d batches ] ; then rm -rf batches ; fi
mkdir batches
let batch=0
let documents_in_batch=0
echo 'Creating batches for parallel processing...'
for journal in input/$prefix ; do
	if [ ! -d "$journal" ] ; then continue ; fi

	for document in $journal/* ; do
		batchdir=batches/$batch
		if [ ! -d $batchdir ] ; then mkdir $batchdir ; fi

		ln -s "../../$journal/`basename $document`" $batchdir

		let documents_in_batch=documents_in_batch+1
		if [[ $documents_in_batch -ge $batchsize ]] ; then
			let documents_in_batch=0
			let batch=batch+1
		fi
	done
done

# Process batches:
for batch in batches/* ; do
	if [ ! -d "$batch" ] ; then continue ; fi

	scheduler

	forkdir=fork_$fork

	rm -rf $forkdir
	mkdir $forkdir
	cd $forkdir

	mkdir input ; cd input ; ln -s ../../$batch ; cd ..

	ln -s ../dictionaries
	mkdir tmp ; cd tmp ; ln -s ../../tmp/* . ; cd ..
	ln -s ../bioknack
	ln -s ../opacmo
	ln -s ../opacmo_data

	echo "Processing in background: batch $batch"
	if [ "$1" = 'pner' ] || [ "$1" = 'all' ]; then
		make_opacmo.sh $cmd "`basename $batch`" &> FORK_LOG &
		sleep 1
	else
		qsub -cwd -N "opacmo.`basename $batch`" -l h_vmem=$maxmem -pe smp $cores -b y "opacmo/make_opacmo.sh $cmd \"`basename $batch`\" &> FORK_LOG"
		sleep 5
	fi

	cd ..
	let fork=fork+1
done

# Wait until all spawned processes have finished:
scheduler
while [[ $? -ne 0 ]] ; do
	sleep 5
	scheduler
done

echo "Processed background processes: $fork"

