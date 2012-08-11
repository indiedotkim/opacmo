#!/usr/bin/ruby

pmcids = {}
entities = {}
scores = []

# Read the PMCIDs, entities and scores:
File.new('tmp/pmcids.tmp', 'r').each_line { |line|
	line.chomp!
	line.strip!

	pmcids[line] = true
}
Dir.glob('opacmo_data/*__yoctogi_genes.tsv').each { |gene_tsv|
	File.new(gene_tsv, 'r').each_line { |line|
		line.chomp!
		line.strip!

		pmcid, entity_name, entity_id, score = line.split("\t")

		entities[entity_id] = entity_name
		scores << score
	}
}

r = Random.new(4927296)
pmcids = pmcids.keys
entity_ids = entities.keys

# Get some permutations:
(1..10000).each { |run|
	permutation = {}

	scores.each { |score|
		pmcid = entity_id = ''

		while permutation.has_key?("#{pmcid = pmcids[r.rand(pmcids.length)]}/#{entity_id = entity_ids[r.rand(entity_ids.length)]}") do
		end

		permutation["#{pmcid}/#{entity_id}"] = score
	}

	# Announce the fantastic news to the world:
	output_file = File.new("tmp/permutation_#{run}.tsv", 'w')
	permutation.each_pair { |pmcid_entity_pair, score|
		pmcid, entity_id = pmcid_entity_pair.split('/', 2)

		output_file.puts "#{pmcid}\t#{entities[entity_id]}\t#{entity_id}\t#{score}"
	}
	output_file.close
}
