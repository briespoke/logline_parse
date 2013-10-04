cat status.log | ruby ../count.rb -H -c '["placement_id", "timestamp", "query.type", "query.description", "query.duration"]' > output.csv
R --vanilla < average_duration.R