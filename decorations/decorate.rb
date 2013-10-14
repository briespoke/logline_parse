require 'rubygems'
require 'date'
require 'active_support/all'
require 'uri'
require 'cgi'
require 'json'
require 'csv'
require 'trollop'
require 'redis'

def log_line_regex
  /(?<ip_address>[0-9\.]+) - - \[(?<timestamp>.+?)\] "(?<uri>.+?)" (?<status>[0-9]+) [0-9]+ "(?<referrer>.+?)" "(?<user_agent>.+?)"/
end

redis = Redis.new(:host => "localhost", :port => 6378)


$stdin.each_line do |line|
  log_line_regex.match(line) do |matches|
    ip = matches[:ip_address]

    addrInfo = redis.hgetall(ip)
    
    puts "#{line.chomp} #{addrInfo["metroCode"]} #{addrInfo["speed"]}"
  end
end
