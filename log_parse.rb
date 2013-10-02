require 'rubygems'
require 'uri'
require 'cgi'
require 'json'
require 'text-table'

class LogParser
  def initialize(format_string)
    @format = JSON.parse(format_string)
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

        request['query'] = query

        @format.each do |spec|
          source = spec.split('.').reduce(request) do |hash, key|
            hash[key] || ''
          end

          totals[spec] ||= {}
          target = totals[spec]

          target[source] ||= 0
          target[source] += 1
        end
      end
    end

    table = []
    widths = {}
    
    totals.keys.each do |metric|
      totals[metric].each do |key, value|
        table << {metric => key, total: value}
        widths[metric] ||= key.size
        widths[metric] = [widths[metric], key.size].max
      end
    end
    @format.each do |spec|
      size = [widths[spec], spec.size].max
      printf("%#{size}s ", spec)
    end
    # printf "\n"
    # puts table
    table.each do |row|
      row.each do |key, value|
        size = widths[key] || 0
        printf("%#{size}s ", value)
      end
      puts("\n")

    end
  end
end

parser = LogParser.new(ARGV[0])

parser.process(STDIN)