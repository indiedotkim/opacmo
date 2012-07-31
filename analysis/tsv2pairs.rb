#!/usr/bin/ruby

header = true

puts "left-hand side\tright-hand side\tavg. weighted support\tavg. weighted confidence\tavg. weighted lift\tavg. weight"

pairs = {}

STDIN.each { |line|
	if header then
		header = false
		next
	end

	columns = line.chomp.strip.split("\t")

	left_items = columns[0].scan(/[^,].+?\ \([A-Z]*:?\d+\)/)
	right_items = columns[1].scan(/[^,].+?\ \([A-Z]*:?\d+\)/)
	support = columns[2].to_f
	confidence = columns[3].to_f
	lift = columns[4].to_f

	weight = 1.0 / (left_items.length + right_items.length)

	left_items.each { |left|
		right_items.each { |right|
			pair_description = pairs["#{left},#{right}"]
			pair_description = [] unless pair_description
			pair_description << [ weight * support, weight * confidence, weight * lift, weight ]
			pairs["#{left},#{right}"] = pair_description
		}
	}
}

pairs.each_pair { |pair, metrics|
	items = pair.scan(/[^,].+?\ \([A-Z]*:?\d+\)/)

	wa_support = metrics.map { |x| x[0] }.inject { |sum, x| sum += x } / metrics.length
	wa_confidence = metrics.map { |x| x[1] }.inject { |sum, x| sum += x } / metrics.length
	wa_lift = metrics.map { |x| x[2] }.inject { |sum, x| sum += x } / metrics.length
	wa_weight = metrics.map { |x| x[3] }.inject { |sum, x| sum += x } / metrics.length

	puts "#{items[0]}\t#{items[1]}\t#{wa_support}\t#{wa_confidence}\t#{wa_lift}\t#{wa_weight}"
}
