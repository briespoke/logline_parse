#!/usr/bin/ruby

require 'rubygems'
require 'date'
require 'active_support/all'
require 'uri'
require 'cgi'
require 'json'
require 'csv'
require 'trollop'
require 'useragent'

module CountVonCount

  class LogParser
    def initialize(format_string, options)
      @format = format_string.split(',').reduce([]) do |result, token|
        result << token.strip
        result
      end
      @options = options
    end

    def log_line_regex
      /(?<ip_address>[0-9\.]+) - - \[(?<timestamp>.+?)\] "(?<uri>.+?)" (?<status>[0-9]+) [0-9]+ "(?<referrer>.+?)" "(?<user_agent>.+?)"/
    end

    def optional_regex
      /(?<dma>\w+?) (?<speed>\w+?)$/
    end

    def placement_regex
      /\/placements\/(?<placement_id>[0-9]+)/
    end

    def line_matches_to_hash(line, matches)
      request = matches.names.reduce({}) {|result, name| result[name] = matches[name]; result}
      
      uri = URI::parse matches[:uri].split(' ')[1]

      placement_regex.match(uri.path) do |placement_matches|
        request['placement_id'] = placement_matches[:placement_id]
      end
      
      query = if uri.query
        uri.query.split('&').reduce({}) do |result, str|
          key, value = str.split '='
          result[key] = value
          result
        end
      else 
        {} 
      end

      request['uri'] = uri.to_s
      request['query'] = query
      agent = UserAgent.parse(request['user_agent'])
      
      request['browser'] = agent.browser
      request['platform'] = agent.platform


      time = DateTime.strptime(request['timestamp'], "%d/%b/%Y:%H:%M:%S %z").new_offset(0)

      if @options[:hours]
        time = time.change(sec: 0).change(min: 0)
      end

      if @options[:days]
        time = time.change(sec: 0).change(min: 0).change(hour: 0)
      end

      request['timestamp'] = time 

      hash = @format.reduce({}) do |result, spec|
        source = spec.split('.').reduce(request) do |request_obj, key|
          request_obj[key] || ''
        end
        result[spec] ||= source

        result
      end
      {hash: hash}
    end
    
    def process_flat(input)
      input.readlines.each do |line|
        log_line_regex.match(line) do |matches|
          hash = line_matches_to_hash(line, matches)

          yield hash
        end
      end

    end

    def process_with_counts(input)
      totals = {}

      input.readlines.each do |line|
        log_line_regex.match(line) do |matches|
          hash = line_matches_to_hash(line, matches)

          hash_key = Marshal::dump(hash)

          totals[hash_key] ||= {hash: hash, total: 0}
          totals[hash_key][:total] += 1
        end
      end

      totals.each do |hash_key, hash|
        yield hash
      end
    end

    def process(input, &block)
      if @options[:aggregate]
        process_with_counts(input, &block)
      else
        process_flat(input, &block)
      end
    end

    def to_csv(input)
      headers = @format

      if @options[:aggregate]
        headers << 'count'
      end
      
      puts headers.to_csv

      process(input) do |record|
        row = record[:hash].values

        if @options[:aggregate]
          row << record[:total]
        end
        puts row.to_csv
      end
    end

    def to_table(input)
      output = ""
      table = []
      widths = {}
      
      process(input) do |row|
        row[:hash].each do |spec, value|
          string_val = value.class == String ? value : value.to_s
          widths[spec] ||= 0

          widths[spec] = [widths[spec], spec.size, string_val.size].max
        end
      end

      unless @options[:quiet]
        @format.each do |spec|
          size = [widths[spec], spec.size].max
          output << sprintf("%#{size}s ", spec)
        end
        output << "count\n"
      end

      @totals.values.each do |row|
        row[:hash].each do |spec, value|
          output << sprintf("%#{widths[spec]}s ", value)
        end
        output << "#{row[:total]}\n"
      end
      output
    end
  end
end

p = Trollop::Parser.new do
  banner <<-EOS
count counts logline elements.

Usage:
      ruby count.rb [options] pathspec [filename]

If no filename is specified, it will read from STDIN.

Pathspec:
      ip_address, timestamp, uri, status, referrer, user_agent, query.[query parameter]

A JSON array of strings, each specifying a path. The paths can either be one of the single values above, or a query parameter specified like this:

      ruby count.rb '["referrer", "query.type"]' status.log

produces the following output:
                                       referrer query.type count
                                              - IMPRESSION 4
                                              -            10
      http://localhost:3000/ad_tags/926000/test            5
      http://localhost:3000/ad_tags/926000/test      start 3
      http://localhost:3000/ad_tags/926000/test   complete 1


count will group based on the fields specified.

Options:
EOS
  opt :quiet, "Use minimal output", short: 'q'
  opt :csv, "Output csv", short: 'c'
  opt :extra, "Use extra data", short: 'e'
  opt :aggregate, "Aggregate counts", short: 'a'
  opt :hours, "Bucket time by hours", short: 'H'
  opt :days, "Bucket time by days", short: 'd'
end

opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty?
  p.parse ARGV
end

spec = ARGV[0]
input = ARGV[1] ? open(ARGV[1]) : STDIN

parser = CountVonCount::LogParser.new(spec, opts)

if opts[:csv]
  puts parser.to_csv(input)
else
  puts parser.to_table(input)
end
