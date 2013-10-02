#!/usr/bin/ruby

require 'rubygems'
require 'uri'
require 'cgi'
require 'json'
require 'trollop'

module CountVonCount
  class LogParser
    def initialize(format_string, options)
      @format = JSON.parse(format_string)
      @options = options
    end

    def log_line_regex
      /(?<ip_address>[0-9\.]+) - - \[(?<timestamp>.+?)\] "(?<uri>.+?)" (?<status>[0-9]+) [0-9]+ "(?<referrer>.+?)" "(?<user_agent>.+?)"/
    end
    
    def process(input)
      totals = {}

      input.readlines.each do |line|
        log_line_regex.match(line) do |matches|
          request = matches.names.reduce({}) {|result, name| result[name] = matches[name]; result}
          
          uri = URI::parse matches[:uri].split(' ')[1]
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

          hash = @format.reduce({}) do |hash, spec|
            source = spec.split('.').reduce(request) do |hash, key|
              hash[key] || ''
            end
            hash[spec] ||= source

            hash
          end
          hash_key = JSON.generate(hash)

          totals[hash_key] ||= {hash: hash, total: 0}
          totals[hash_key][:total] += 1
        end
      end

      table = []
      widths = {}
      
      totals.values.each do |row|
        row[:hash].each do |spec, value|
          widths[spec] ||= 0
          widths[spec] = [widths[spec], spec.size, value.size].max
        end
      end

      unless @options[:quiet]
        @format.each do |spec|
          size = [widths[spec], spec.size].max
          printf("%#{size}s ", spec)
        end
        puts "count"
      end

      totals.values.each do |row|
        row[:hash].each do |spec, value|
          printf("%#{widths[spec]}s ", value)
        end
        puts row[:total]
      end

    end
  end
end

p = Trollop::Parser.new do
  opt :quiet, "Use minimal output", :short => 'q'
  banner <<-EOS
count counts logline elements.

Usage:
      ruby count.rb [options] pathspec [filename]

If no filename is specified, it will read from STDIN.

pathspec:

A JSON array of strings, each specifying a path. Such as:

      ruby count.rb '["uri", "referrer", "query.type"]'

count will group based on the fields specified.

options:
EOS
end

opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty?
  p.parse ARGV
end

spec = ARGV[0]
input = ARGV[1] ? open(ARGV[1]) : STDIN

parser = CountVonCount::LogParser.new(spec, opts)
parser.process(input)