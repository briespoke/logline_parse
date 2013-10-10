#!/usr/bin/ruby

require 'rubygems'
require 'date'
require 'active_support/all'
require 'uri'
require 'cgi'
require 'json'
require 'csv'
require 'trollop'

module CountVonCount
  class MeanAggregator < Array
    def to_s
      unless @aggregate && @aggregate_size == size
        sum = reduce(:+)
        @aggregate = sum.to_f / size.to_f
        @aggregate_size = size
      end
      @aggregate.round(2).to_s
    end
  end

  class LogParser
    def initialize(format_string, options)
      @format_fields_in_order = []
      @aggregates = {}
      @format = format_string.split(',').reduce({}) do |result, token|
        field, flags = token.split('=').map {|t| t.strip}
        result[field] = flags
        unless flags.nil?
          @aggregates[field] = flags
        end
        @format_fields_in_order << field
        result
      end
      @options = options
    end

    def log_line_regex
      /(?<ip_address>[0-9\.]+) - - \[(?<timestamp>.+?)\] "(?<uri>.+?)" (?<status>[0-9]+) [0-9]+ "(?<referrer>.+?)" "(?<user_agent>.+?)"/
    end

    def placement_regex
      /\/placements\/(?<placement_id>[0-9]+)/
    end
    
    def process(input)
      totals = {}

      input.readlines.each do |line|
        log_line_regex.match(line) do |matches|
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

          time = DateTime.strptime(request['timestamp'], "%d/%b/%Y:%H:%M:%S %z").new_offset(0)

          if @options[:hours]
            time = time.change(sec: 0).change(min: 0)
          end

          if @options[:days]
            time = time.change(sec: 0).change(min: 0).change(hour: 0)
          end

          request['timestamp'] = time 

          hash = @format.reduce({}) do |result, (spec, options)|
            unless options.blank?
              result[spec] ||= nil
            else
	      source = spec.split('.').reduce(request) do |request_obj, key|
	        request_obj[key] || ''
	      end
	      result[spec] ||= source
            end
  
    	    result
          end
          hash_key = Marshal::dump(hash)

          totals[hash_key] ||= {hash: hash, total: 0}
          totals[hash_key][:total] += 1
          @aggregates.each do |spec, type|
	    source = spec.split('.').reduce(request) do |request_obj, key|
	      request_obj[key] || ''
	    end
            totals[hash_key][:hash][spec] ||= MeanAggregator.new
            totals[hash_key][:hash][spec] << source.to_i
          end
        end
      end

      @totals = totals
    end

    def to_csv
      csv_string = CSV.generate do |csv|
        csv << @format_fields_in_order + ["count"]

        @totals.values.each do |record|
          row = []
          record[:hash].each do |spec, value|
            row << value
          end
          row << record[:total]

          csv << row
        end
      end
      csv_string
    end

    def to_table
      output = ""
      table = []
      widths = {}
      
      @totals.values.each do |row|
        row[:hash].each do |spec, value|
          $stderr.puts value.class
          string_val = value.class == String ? value : value.to_s
          widths[spec] ||= 0

          widths[spec] = [widths[spec], spec.size, string_val.size].max
        end
      end

      unless @options[:quiet]
        @format_fields_in_order.each do |spec|
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
parser.process(input)

if opts[:csv]
  puts parser.to_csv
else
  puts parser.to_table
end
