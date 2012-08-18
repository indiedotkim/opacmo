#!/usr/bin/ruby

occurrence_pairs = {}
last_pmcid = ''
publication_gene_set = {}

Dir['./opacmo_data/*__yoctogi_genes.tsv'].each { |gene_file|
	IO.readlines(gene_file).each { |line|
		line.chomp!

		pmcid, gene_symbol, gene_id, score = line.split("\t")

		unless pmcid == last_pmcid then
			publication_gene_set.keys.sort.combination(2).to_a.each { |pair|
				key = pair.join('//')

				occurrences = occurrence_pairs[key] || 0
				occurrences += 1

				occurrence_pairs[key] = occurrences
			}

			publication_gene_set.clear
			last_pmcid = pmcid
		end

		publication_gene_set["#{gene_symbol}\t#{gene_id}"] = true
	}
}

puts "# gene symbol 1\tEntrez Gene ID 1\tgene symbol 2\tEntrez Gene ID 2\tco-occurrences"
occurrence_pairs.each_pair { |pair, occurrences|
	x, y = pair.split('//')

	puts "#{x}\t#{y}\t#{occurrences}"
}

