in_edge = false
node = origin = destination = support = confidence = lift = ''
nodes = {}
STDIN.each { |line|
	line.chomp!.strip!

	if in_edge and line == '];' then
		puts "#{nodes[origin]}\t#{nodes[destination]}\t#{support}\t#{confidence}\t#{lift}" if in_edge
		in_edge = false
	end
	
	nodes[node] = line.split('=')[1][2..-3] if line.start_with?('label=')
	
	support = line.split('=')[1] if line.start_with?('support=')
	confidence = line.split('=')[1] if line.start_with?('confidence=')
	lift = line.split('=')[1] if line.start_with?('lift=')

	node_match = line.match(/^(\d+)\s\[$/)
	node = node_match[1] if node_match

	edge_match = line.match(/^(\d+)\s\->\s(\d+)\s\[$/)
	if edge_match then
		origin = edge_match[1]
		destination = edge_match[2]
		in_edge = true
	end
}
