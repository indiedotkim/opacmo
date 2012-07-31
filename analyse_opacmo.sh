#!/bin/bash

TOP_N=100
SINGLE_FORMAT_FILE=tmp/single.tmp

# Individual entities can be extracted as follows:
## BRCA2
#create_single_file 675 genes human
## TP53
#create_single_file 7157 genes human
## cancer
#create_single_file 'DOID:162' terms_do
## breast cancer
#create_single_file 'DOID:1612' terms_do
## kidney cancer
#create_single_file 'DOID:263' terms_do
## tonsillitis
#create_single_file 'DOID:10456' terms_do
## common cold
#create_single_file 'DOID:10459' terms_do

rm -f $SINGLE_FORMAT_FILE $SINGLE_FORMAT_FILE.tmp

create_single_file() {
	TERM=$1
	CATEGORY=$2

	for results in opacmo_data/*__yoctogi_$CATEGORY.tsv ; do
		<$results grep -E "^[0-9]+	[^	]*	$TERM	" \
			| cut -f 1,2,3 \
			| awk -F '	' '{ print $1"\t"$2" ("$3")" }' \
			| sort -k 1,1 >> $SINGLE_FORMAT_FILE.tmp
	done
}

get_top_n() {
	N=$1
	CATEGORY=$2
	FILTER=$3

	cut -f 3 opacmo_data/*__yoctogi_$CATEGORY.tsv \
		| sort \
		| uniq -c \
		| sed -E 's/^[ ]+//' \
		| sort -t ' ' -k 1,1 -n -r \
		| sed -E 's/^[0-9]+ //' > tmp/top_${N}_$CATEGORY.tmp.tmp

	if [[ "$FILTER" == "human" ]] ; then
		grep -E '	9606\|[0-9]+$' tmp/entrez_genes \
			| cut -f 2 -d '	' \
			| cut -f 2 -d '|' \
			| sort | uniq > tmp/entrez_genes.human
		<tmp/top_${N}_$CATEGORY.tmp.tmp ruby -e '
				accepted_genes = {}
				File.new("tmp/entrez_genes.human", "r").each_line { |gene|
					accepted_genes[gene] = true
				}
				STDIN.each_line { |gene|
					puts gene if accepted_genes.has_key?(gene)
				}
			' > tmp/top_${N}_$CATEGORY.tmp2
		<tmp/top_${N}_$CATEGORY.tmp2 head -n $N > tmp/top_${N}_$CATEGORY.tmp
		rm -f tmp/entrez_genes.human tmp/top_${N}_$CATEGORY.tmp2
	else
		head -n $N tmp/top_${N}_$CATEGORY.tmp.tmp > tmp/top_${N}_$CATEGORY.tmp
	fi

	rm -f tmp/top_${N}_$CATEGORY.tmp.tmp
}

for category in {'genes','terms_go','terms_do','terms_chebi'} ; do
	filter=''

	if [[ "$category" == "genes" ]] ; then
		filter=human
	fi

	get_top_n $TOP_N $category $filter

	for entity in `cat tmp/top_${TOP_N}_$category.tmp` ; do
		create_single_file "$entity" $category
	done
done

sort $SINGLE_FORMAT_FILE.tmp | uniq > $SINGLE_FORMAT_FILE
rm -f $SINGLE_FORMAT_FILE.tmp

<opacmo/analysis/hypothesis_testing.r R --no-save

<tmp/rules.dot ruby opacmo/analysis/dot2tsv.rb > tmp/rules.tsv

