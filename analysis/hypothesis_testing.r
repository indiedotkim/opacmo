library('arulesViz')

tr <- read.transactions("tmp/single.tmp", format = "single", cols = c(1,2), sep = "\t")

rules <- apriori(tr, parameter=list(support = 0.0001, confidence = 0.95, minlen = 2, maxlen = 4, target = 'rules'), control = list(memopt = TRUE))
subrules <- rules[quality(rules)$support >= 0.01]

png("grouped.png", height=4000, width=6000, unit="px", pointsize=10, res = 150)
plot(rules, method = 'grouped', control = list(k = 150))
dev.off()

saveAsGraph(rules, "tmp/rules.dot", format="dot")

#png("matrix.png", height=800, width=1600, unit="px", pointsize=11)
#plot(subrules, method="matrix", measure = c("lift", "confidence"), control = list(reorder = TRUE))
#dev.off()

#png("graph_sets.png", height=6000, width=6000, unit="px", pointsize=10, res = 150)
#plot(rules, method = 'graph')
#dev.off()

#png("graph_items.png", height=6000, width=6000, unit="px", pointsize=10, res = 150)
#plot(rules, method = 'graph', control = list(type = 'items'))
#dev.off()

