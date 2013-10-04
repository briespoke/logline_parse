data = read.csv("output.csv")
clean = data[rowSums(is.na(data)) == 0,]

summary = aggregate(
  clean$query.duration * clean$count, 
  by = list(
    clean$query.description,
    clean$query.type),
  FUN=mean)

print(summary)
