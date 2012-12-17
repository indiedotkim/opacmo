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

# Ruby is directly used by the opacmo pipeline and it is supported for plugins:
ruby_interpreter=ruby

# Python is not used by the opacmo pipeline, but it is supported for plugins:
python_interpreter=python

PATH=$PATH:./opacmo:./bioknack
IFS=$(echo -e -n "\n\b")

# Needed to handle 'interesting' implementation of `sort`/`join` on Linux:
LANG="C"
LC_ALL="C"
LC_COLLATE="C"

# This is actually not used, but preserved here for future applications.
#
# Parameters:
#  1. TSV filename. Third column of the TSV needs to hold the score.
#  2. n
#  3. m
#
#    Takes the value from the sorted (descreasing) list of scores at
#    index: column_length * n / m
#
#    For median, use n = 1 and m = 2.
#    For upper quartile, use n = 1 and m = 4.
#    For lower quartile, use n = 3 and m = 4.
#
get_cut_value() {
	index=`cut -f 3 "$1" | sort -n -r | grep -v -w '1' | wc -l`
	let index=index*$2/$3
	if [[ $index -lt 1 ]] ; then index=1 ; fi
	return `cut -f 3 "$1" | sort -n -r | head -n $index | tail -n 1`
}

# Note: Also rewrites identifiers like BMC_Genomics-6--554113 to
#       their PubMed Central ID. Here, the PMC-ID would be 554113.
cut_below() {
	sed $sed_regexp 's/^.+-([0-9]+)	/\1	/' $2 \
		| ruby -e "STDIN.each { |l|
				l.chomp!
				cols = l.split(\"\\t\")
				puts cols.join(\"\\t\") if cols[-1].to_i >= $1
			}" \
		| sort -k 1 > $2.tmp
}

generate_dimensions() {
	pmcfile=$1
	outfile=$2

	echo "   - generating Yoctogi dimension tables"

	echo "     - publication PMIDs"
	join -t "	" -1 1 -2 1 -o 0,2.2 $pmcfile pmid.tsv | uniq \
		> $pmcfile.tmp

	echo "     - publication DOIs"
	join -t "	" -1 1 -2 1 -o 0,1.2,2.2 $pmcfile.tmp doi.tsv | uniq \
		> $pmcfile.tmp2

	echo "     - publication titles"
	join -t "	" -1 1 -2 1 -o 0,1.2,1.3,2.2 $pmcfile.tmp2 titles.tsv | uniq \
		> $pmcfile.tmp

	echo "     - publication journals"
	join -t "	" -1 1 -2 1 -o 0,1.2,1.3,1.4,2.2 $pmcfile.tmp journals.tsv | uniq \
		> $pmcfile.tmp2

	echo "     - publication years"
	join -t "	" -1 1 -2 1 -o 0,1.2,1.3,1.4,1.5,2.2 $pmcfile.tmp2 year.tsv | uniq \
		> $outfile

	rm -f $pmcfile.tmp $pmcfile.tmp2
}

extend_with_aggregate() {
	tablefile=$1
	extrafile=$2

	echo "  - adding aggregate data from $extrafile"

	<"$tablefile" $ruby_interpreter -e "xtra = {} ; File.open(\"$extrafile\", 'r').each_line { |line|
		chunks = line.chomp.split(\"\\t\", 2);
		aggregate = xtra[chunks[0]] || [];
		aggregate << chunks[1].split(\"\\t\");
		xtra[chunks[0]] = aggregate;
	}
	STDIN.each { |line|
		chunks = line.split(\"\\t\", 2);
		aggregate = xtra[chunks[0]] || [];
		aggregate = aggregate.sort { |x, y| y[2].to_i <=> x[2].to_i }.map { |x| x.join('@!@') };
		puts \"#{line.chomp}\\t#{aggregate.join('#!#')}\"
	}" > $tablefile.tmp

	rm -f $tablefile
	mv $tablefile.tmp $tablefile
}

check_dir() {
	if [ ! -d "./$1" ] ; then
		echo "This script needs to be executed where './$1' is present."
		echo ""
		echo "In other words: the directory '$1' needs to be found in the"
		echo "current working directory when you execute this script."
		exit 1
	fi
}

run_plugins() {
	joinpoint=$1
	state=$2

	for plugin in opacmo/plugins/${joinpoint}_${state}_*.{sh,rb,py} ; do
		if [ -f "$plugin" ] ; then
			if [ "${plugin##*.}" = 'sh' ] ; then
				bash "$plugin"
			elif [ "${plugin##*.}" = 'rb' ] ; then
				$ruby_interpreter "$plugin"
			elif [ "${plugin##*.}" = 'py' ] ; then
				$python_interpreter "$plugin"
			fi
		fi
	done
}

help_message() {
	echo "Usage: make_opacmo.sh command [prefix]"
	echo ""
	echo "Options for 'command' (applicable only on local machines):"
	echo "  all          : all of the options below in the listed order"
	echo "  freeze       : jot down the current state of opacmo/bioknack for versioning"
	echo "  get          : download gene and species databases, ontologies and PMC archive"
	echo "  dictionaries : create dictionaries for bioknack's named entity recognition"
	echo "  ner          : run bioknack's named entity recognition ('prefix' applicable)"
	echo "  pner         : run bioknack's parallelized named entity recognition (default)"
	echo "  tsv          : filter and join NER output into TSV files"
	echo "  labels       : create TSV files that map identifiers to readable names"
	echo "  yoctogi      : create TSV files for loading into Yoctogi"
	echo ""
	echo "High performance cluster options for 'command':"
	echo "  bundle       : execute 'freeze', 'get' and 'dictionaries' from above and then"
	echo "                 creates a tar file ('bundle.tar') for transferral onto a Sun"
	echo "                 Grid Engine powered cluster"
	echo "  sge          : after extracing a bundle from the previous step, continues with"
	echo "                 the steps 'pner' (cluster version), 'tsv', 'labels' and 'yoctogi'"
	echo ""
	echo "Amazon Elastic Compute Cloud (EC2) options for 'command':"
	echo "  ec2ondemand  : execute 'all' on EC2 on-demand instances of fixed price"
	echo "  ec2spot      : execute 'all' on EC2 spot instances of variable price"
	echo ""
	echo "The optinal parameter 'prefix' can be used to carry out a NER run on"
	echo "a subset of PMC. For example, the prefix '\"BMC_*\"' restricts the NER run"
	echo "to journal directories starting with 'BMC_'."
}

check_dir 'opacmo'
check_dir 'bioknack'

if [[ $# -lt 1 ]] || [[ $# -gt 2 ]] ; then
	help_message
	exit 1
fi

if [ "$1" != 'all' ] && [ "$1" != 'freeze' ] && [ "$1" != 'get' ] && [ "$1" != 'dictionaries' ] && [ "$1" != 'ner' ] && [ "$1" != 'pner' ] && [ "$1" != 'tsv' ] && [ "$1" != 'labels' ] && [ "$1" != 'yoctogi' ]  && [ "$1" != 'bundle' ] && [ "$1" != 'sge' ] && [ "$1" != 'ec2ondemand' ] && [ "$1" != 'ec2spot' ] && [ "$1" != 'pluginexample' ] ; then
	help_message
	exit 1
fi

prefix=*
data_dir=opacmo_data

# Should the data be denormalised? If you plan to use Yoctogi, then you either need to
# denormalize and use a Yoctogi fact table, or you do not denormalize and use fact table
# partitions.
denormalize=0

# If denormalize=1, should we also generate lower case versions of gene-/species- and term-names?
# This is required if MongoDB is used as a backend, because MongoDB cannot generate to indices on
# one column.
lowercase=0

if [[ $# -eq 2 ]] ; then
	prefix=$2
fi

if [ "$1" = 'ec2' ] ; then
	# TODO Check if ec2 dir present
	# EC2_HOME=`pwd`/`ls | grep 'ec2-api-tools-'`
	X=
fi

if [ "$1" = 'pluginexample' ] ; then
	touch STATE_PLUGINEXAMPLE
	echo "Running plugin examples..."

	run_plugins pre pluginexample

	rm -f STATE_PLUGINEXAMPLE
fi

if [ "$1" = 'all' ] || [ "$1" = 'freeze' ] || [ "$1" = 'bundle' ] || [ "$1" = 'ec2ondemand' ] || [ "$1" = 'ec2spot' ] ; then
	touch STATE_FREEZE
	echo "Freezing current version information..."

	cd bioknack
	git show-ref --head > ../VERSION_BIOKNACK_REF
	git diff > ../VERSION_BIOKNACK_DIFF
	cd ..

	cd opacmo
	git show-ref --head > ../VERSION_OPACMO_REF
	git diff > ../VERSION_OPACMO_DIFF
	cd ..

	bash -version > VERSION_BASH
	$ruby_interpreter -v > VERSION_RUBY
	rm -f STATE_FREEZE
fi

if [ "$1" = 'sge' ] ; then
	touch STATE_FREEZE
	bash -version > VERSION_CLUSTER_BASH
	$ruby_interpreter -v > VERSION_CLUSTER_RUBY
	rm -f STATE_FREEZE
fi

if [ "$1" = 'ec2ondemand' ] || [ "$1" = 'ec2spot' ] ; then
	touch STATE_FREEZE
	ls | grep 'ec2-api-tools-' > VERSION_EC2_TOOLS
	echo "$ami" > VERSION_AMI
	rm -f STATE_FREEZE
fi

if [ "$1" = 'ec2ondemand' ] || [ "$1" = 'ec2spot' ] ; then
	touch STATE_EC2_BOOT
	aws_opacmo.sh `echo -n "$1" | sed $sed_regexp 's/^ec2//'`
	rm -f STATE_EC2_BOOT
fi

if [ "$1" = 'all' ] || [ "$1" = 'get' ] || [ "$1" = 'bundle' ] ; then
	touch STATE_GET
	date > VERSION_DATA_INFO
	mkdir input dictionaries tmp
	bk_ner_gn.sh minimal
	bk_ner_gn.sh obo
	bk_ner_gn.sh pmc
	rm -f STATE_GET
fi

if [ "$1" = 'all' ] || [ "$1" = 'dictionaries' ] || [ "$1" = 'bundle' ] ; then
	touch STATE_DICTIONARIES
	bk_ner_gn.sh genes
	bk_ner_gn.sh species
	rm -f STATE_DICTIONARIES
fi

if [ "$1" = 'bundle' ] ; then
	tar cf bundle.tar BIOKNACK_REF BIOKNACK_DIFF OPACMO_REF OPACMO_DIFF DATA_INFO VERSION_BASH VERSION_RUBY opacmo bioknack input dictionaries tmp
	echo "Created the file 'bundle.tar'. Transfer this file onto your cluster,"
	echo "untar it, and then run './make_opacmo.sh sge'."
	exit 0
fi

if [ "$1" = 'all' ] || [ "$1" = 'ner' ] || [ "$1" = 'pner' ] || [ "$1" = 'sge' ] ; then
	if [ "$1" = 'ner' ] ; then
		touch STATE_NER
		if [ ! -d opacmo_data ] ; then mkdir opacmo_data ; fi

		for journal_dir in input/$prefix ; do

			if [ ! -d "$journal_dir" ] ; then continue ; fi

			echo "$journal_dir"
			bk_ner_symlink_dir.sh "$journal_dir"
			bk_ner_gn.sh corpus
			bk_ner_gn.sh ner
			bk_ner_gn.sh score

			if [ ! -f genes.tsv ] ; then touch genes.tsv ; fi
			if [ ! -f species.tsv ] ; then touch species.tsv ; fi
			if [ ! -f terms_go.tsv ] ; then touch terms_go.tsv ; fi
			if [ ! -f terms_do.tsv ] ; then touch terms_do.tsv ; fi
			if [ ! -f terms_chebi.tsv ] ; then touch terms_chebi.tsv ; fi

			journal_name=`basename "$journal_dir"`
			cp genes.tsv "opacmo_data/${journal_name}__genes.tsv"
			cp species.tsv "opacmo_data/${journal_name}__species.tsv"
			cp terms_go.tsv "opacmo_data/${journal_name}__terms_go.tsv"
			cp terms_do.tsv "opacmo_data/${journal_name}__terms_do.tsv"
			cp terms_chebi.tsv "opacmo_data/${journal_name}__terms_chebi.tsv"

			rm -f genes.tsv species.tsv terms_*.tsv
		done
		rm -f STATE_NER
	else
		touch STATE_PNER
		if [ ! -d opacmo_data ] ; then mkdir opacmo_data ; fi
		pmake_opacmo.sh $1 "$prefix"
		rm -f STATE_PNER
	fi
fi

if [ "$1" = 'all' ] || [ "$1" = 'tsv' ] || [ "$1" = 'sge' ] ; then
	touch STATE_TSV
	echo "Filtering and joining genes, species and ontology terms..."

	echo " - generating a species white list for filtering species name abbreviations"
	# Create a whitelist of species names to include. Remove genus entities.
	$awk_interpreter -F "\t" '{print $3"\t"$1}' dictionaries/names.dmp | grep -E '^.+ [^	]' \
		| sort -t "	" -k 1,1 > $data_dir/all_species.tmp
	sort -k 1,1 -t "	" tmp/species > $data_dir/species.tmp
	join -t "	" -1 1 -2 1 -o 0,2.2 $data_dir/species.tmp $data_dir/all_species.tmp | uniq \
		| sort -t "	" -k 2,2 > $data_dir/whitelist._tmp

	for genes in $data_dir/*__genes.tsv ; do
		echo " - processing `basename "$genes" __genes.tsv`..."
		species=$data_dir/`basename "$genes" __genes.tsv`__species.tsv
		terms_go=$data_dir/`basename "$genes" __genes.tsv`__terms_go.tsv
		terms_do=$data_dir/`basename "$genes" __genes.tsv`__terms_do.tsv
		terms_chebi=$data_dir/`basename "$genes" __genes.tsv`__terms_chebi.tsv

		tmp=`dirname "$genes"`
		# Postfix is added below. Depends on whether we denormalize or not...
		out=$data_dir/`basename "$genes" __genes.tsv`

		cut_below 3 $genes
		cut_below 3 $species
		cut_below 3 $terms_go
		cut_below 3 $terms_do
		cut_below 3 $terms_chebi

		sort -t "	" -k 2,2 $species.tmp > $species.tmp2
		join -t "	" -1 2 -2 2 -o 1.1,0,1.3 $species.tmp2 $data_dir/whitelist._tmp \
			| sort -t "	" -k 1 > $species.tmp

		if [[ $denormalize -eq 1 ]] ; then
			join -t "	" -a 1 -a 2 -1 1 -2 1 -o 0,1.2,1.3,2.2,2.3 $genes.tmp $species.tmp > $tmp/genes_species.tmp
			join -t "	" -a 1 -a 2 -1 1 -2 1 -o 0,1.2,1.3,1.4,1.5,2.2,2.3 $tmp/genes_species.tmp $terms_go.tmp > $tmp/genes_species_go.tmp
			join -t "	" -a 1 -a 2 -1 1 -2 1 -o 0,1.2,1.3,1.4,1.5,1.6,1.7,2.2,2.3 $tmp/genes_species_go.tmp $terms_do.tmp > $tmp/genes_species_go_do.tmp
			join -t "	" -a 1 -a 2 -1 1 -2 1 -o 0,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,2.2,2.3 $tmp/genes_species_go_do.tmp $terms_chebi.tmp > ${out}__joined.tsv
		else
			cp $genes.tmp ${out}__genes_processed.tsv
			cp $species.tmp ${out}__species_processed.tsv
			cp $terms_go.tmp ${out}__terms_go_processed.tsv
			cp $terms_do.tmp ${out}__terms_do_processed.tsv
			cp $terms_chebi.tmp ${out}__terms_chebi_processed.tsv

			# Keep track of the PMC IDs:
			cut -f 1 ${out}__*_processed.tsv | uniq | sort | uniq > ${out}__pmcids_processed.tsv
		fi

		rm -f $genes.tmp $species.tmp $species.tmp2 $terms.tmp $tmp/*.tmp
	done

	rm -f $data_dir/all_species.tmp $data_dir/whitelist._tmp
	rm -f STATE_TSV
fi

if [ "$1" = 'all' ] || [ "$1" = 'labels' ] || [ "$1" = 'sge' ] ; then
	touch STATE_LABELS
	echo "Generate labels for gene-, species- and ontology-identifiers..."
	bk_ner_fmt_labels.sh
	rm -f STATE_LABELS
fi

if [ "$1" = 'all' ] || [ "$1" = 'yoctogi' ] || [ "$1" = 'sge' ] ; then
	touch STATE_YOCTOGI
	echo "Adding human readable titles, names and terms..."

	# Extract species names and remove genus entities:
	echo " - creating a species name dictionary without genus names"
	grep -E '	.+ [^ ]' species_names.tsv > $data_dir/species_names.tmp

	if [[ $denormalize -eq 1 ]] ; then
		for joined in $data_dir/*__joined.tsv ; do
			if [ ! -f "$joined" ] ; then continue ; fi

			echo " - processing `basename $joined __joined.tsv`"

			echo "   - generating Yoctogi main table"

			# The joined TSV has this column structure:
			#   1. PMC ID
			#   2. gene ID
			#   3. gene score
			#   4. species ID
			#   5. species score
			#   6. GO ID
			#   7. GO score
			#   8. DO ID
			#   9. DO score
			#  10. ChEBI ID
			#  11. ChEBI score

			echo "     - adding gene names"
			sort -k 2,2 -t "	" "$joined" > $joined.tmp
			join -t "	" -a 1 -1 2 -2 1 -o 1.1,2.2,0,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11 "$joined.tmp" gene_names.tsv \
				| $awk_interpreter -F "\t" '{if ($3 == "" || $2 != "") {print $0}}' > $joined.tmp2

			echo "     - adding species names"
			sort -k 5,5 -t "	" "$joined.tmp2" > $joined.tmp
			join -t "	" -a 1 -1 5 -2 1 -o 1.1,1.2,1.3,1.4,2.2,0,1.6,1.7,1.8,1.9,1.10,1.11,1.12 "$joined.tmp" $data_dir/species_names.tmp \
				| $awk_interpreter -F "\t" '{if ($6 == "" || $5 != "") {print $0}}' > $joined.tmp2

			echo "     - adding GO ontology term-names"
			sort -k 8,8 -t "	" "$joined.tmp2" > $joined.tmp
			join -t "	" -a 1 -1 8 -2 1 -o 1.1,1.2,1.3,1.4,1.5,1.6,1.7,2.2,0,1.9,1.10,1.11,1.12,1.13 "$joined.tmp" term_names.tsv \
				| $awk_interpreter -F "\t" '{if ($9 == "" || $8 != "") {print $0}}' > $joined.tmp2

			echo "     - adding DO ontology term-names"
			sort -k 11,11 -t "	" "$joined.tmp2" > $joined.tmp
			join -t "	" -a 1 -1 11 -2 1 -o 1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,2.2,0,1.12,1.13,1.14 "$joined.tmp" term_names.tsv \
				| $awk_interpreter -F "\t" '{if ($12 == "" || $11 != "") {print $0}}' > $joined.tmp2

			echo "     - adding ChEBI ontology term-names"
			sort -k 14,14 -t "	" "$joined.tmp2" > $joined.tmp
			join -t "	" -a 1 -1 14 -2 1 -o 1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11,1.12,1.13,2.2,0,1.15 "$joined.tmp" term_names.tsv \
				| $awk_interpreter -F "\t" '{if ($15 == "" || $14 != "") {print $0}}' > $joined.tmp2

			# Convert text fields to lowercase for use with MongoDB. Only convert those fields
			# for which no programmatic solution can be provided to look up even case-sensitive
			# entries.
			if [ $lowercase -eq 1 ] ; then
				echo "     - adding lower case versions of gene-, species- and term-names"
				$awk_interpreter -F "\t" '{
						gene="";
						if ($2 ~ /[A-Za-z0-9]/) {gene=tolower($2)};
						species="";
						if ($5 ~ /[A-Za-z0-9]/) {species=tolower($5)};
						term_go="";
						if ($8 ~ /[A-Za-z0-9]/) {term_go=tolower($8)};
						term_do="";
						if ($11 ~ /[A-Za-z0-9]/) {term_do=tolower($11)};
						term_chebi="";
						if ($14 ~ /[A-Za-z0-9]/) {term_chebi=tolower($14)};
						print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8"\t"$9"\t"$10"\t"$11"\t"$12"\t"$13"\t"$14"\t"$15"\t"$16"\t"gene"\t"species"\t"term_go"\t"term_do"\t"term_chebi
					}' "$joined.tmp2" \
					> $data_dir/`basename $joined __joined.tsv`__yoctogi.tsv
			else
				mv "$joined.tmp2" $data_dir/`basename $joined __joined.tsv`__yoctogi.tsv
			fi

			generate_dimensions "$joined" $data_dir/`basename $joined __joined.tsv`__yoctogi_publications.tsv
		done
	else
		# If we do not denormalize, then arrange the TSVs so that they can be loaded into partitions:
		for genes in $data_dir/*__genes_processed.tsv ; do
			if [ ! -f "$genes" ] ; then continue ; fi

			echo " - processing `basename $genes __genes_processed.tsv`"
			pmcids=$data_dir/`basename "$genes" __genes_processed.tsv`__pmcids_processed.tsv
			species=$data_dir/`basename "$genes" __genes_processed.tsv`__species_processed.tsv
			terms_go=$data_dir/`basename "$genes" __genes_processed.tsv`__terms_go_processed.tsv
			terms_do=$data_dir/`basename "$genes" __genes_processed.tsv`__terms_do_processed.tsv
			terms_chebi=$data_dir/`basename "$genes" __genes_processed.tsv`__terms_chebi_processed.tsv

			# Postfix is added below.
			out=$data_dir/`basename $genes __genes_processed.tsv`

			echo "   - adding gene names"
			sort -k 2,2 -t "	" "$genes" > $genes.tmp
			join -t "	" -1 2 -2 1 -o 1.1,2.2,0,1.3 "$genes.tmp" gene_names.tsv > ${out}__yoctogi_genes.tsv

			echo "   - adding species names"
			sort -k 2,2 -t "	" "$species" > $species.tmp
			join -t "	" -1 2 -2 1 -o 1.1,2.2,0,1.3 "$species.tmp" $data_dir/species_names.tmp > ${out}__yoctogi_species.tsv

			echo "   - adding GO ontology term-names"
			sort -k 2,2 -t "	" "$terms_go" > $terms_go.tmp
			join -t "	" -1 2 -2 1 -o 1.1,2.2,0,1.3 "$terms_go.tmp" term_names.tsv > ${out}__yoctogi_terms_go.tsv

			echo "   - adding DO ontology term-names"
			sort -k 2,2 -t "	" "$terms_do" > $terms_do.tmp
			join -t "	" -1 2 -2 1 -o 1.1,2.2,0,1.3 "$terms_do.tmp" term_names.tsv > ${out}__yoctogi_terms_do.tsv

			echo "   - adding ChEBI ontology term-names"
			sort -k 2,2 -t "	" "$terms_chebi" > $terms_chebi.tmp
			join -t "	" -1 2 -2 1 -o 1.1,2.2,0,1.3 "$terms_chebi.tmp" term_names.tsv > ${out}__yoctogi_terms_chebi.tsv

			# Keep track of the IDs that made it into the Yoctogi tables:
			# (Obsolete term names will have been dropped now.)
			cut -f 1 "${out}"__yoctogi_*.tsv | uniq | sort | uniq > ${out}__yoctogi_pmcids.tsv

			generate_dimensions $pmcids "${out}"__yoctogi_publications.tsv
			extend_with_aggregate "${out}"__yoctogi_publications.tsv "${out}"__yoctogi_genes.tsv
			extend_with_aggregate "${out}"__yoctogi_publications.tsv "${out}"__yoctogi_species.tsv
			extend_with_aggregate "${out}"__yoctogi_publications.tsv "${out}"__yoctogi_terms_go.tsv
			extend_with_aggregate "${out}"__yoctogi_publications.tsv "${out}"__yoctogi_terms_do.tsv
			extend_with_aggregate "${out}"__yoctogi_publications.tsv "${out}"__yoctogi_terms_chebi.tsv

			rm -f $genes.tmp $species.tmp $terms_go.tmp $terms_do.tmp $terms_chebi.tmp
		done
	fi

	rm -f $data_dir/species_names.tmp
	rm -f STATE_YOCTOGI
fi

