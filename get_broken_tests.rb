require 'pry'
require 'json'
require 'net/http'

BK_TOKEN = ENV['BK_TOKEN'].freeze

def bk_fetch(uri)
  res = Net::HTTP.get_response(URI.parse("#{uri}?access_token=#{BK_TOKEN}"))
  if res['Content-Type']&.include?('application/json')
    JSON.parse(res.body)
  else
    res.body
  end
end

def fetch_build(build_id)
  bk_fetch("https://api.buildkite.com/v2/organizations/gusto/pipelines/zenpayroll/builds/#{build_id}/")
end

def failed_specs_from_log(colorized_content, only_files: false)
  content = colorized_content.gsub(/\e\[([;\d]+)?m/, '')
  examples = content.lines.flat_map { |l| l.match(/rspec (\'*\.\/spec.*).*/)&.captures }.compact.map { |l| l[0, l.index('#')].strip }.map { |l| l.gsub(/\A'/, '').gsub(/'\z/, '') }
  if only_files
    examples.map { |e| e.slice(0, e.rindex('.rb')+3) }
  else
    examples
  end
end

require 'optparse'

options = { files: false, short: false }
opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{__FILE__} [options] [ZP_BUILD_ID]"

  opts.on("-f", "--files", "Only print files") do |o|
    options[:files] = o
  end

  opts.on('-s', '--short', 'Short output for rspec') do |o|
    options[:short] = o
  end
end
opt_parser.parse!

build_id = ARGV[0]&.to_i

if build_id.nil?
  puts "Missing ZP_BUILD_ID"
  puts
  puts opt_parser
  exit 1
end

build = fetch_build(build_id)
failed_jobs = build['jobs'].select { |j| j['state'] == 'failed' }
log_file_paths = failed_jobs.map { |j| j['raw_log_url'] }

unless options[:short]
  puts "Failed specs:"
  puts "################"
  puts ""
end
failed_so_far = []
log_file_paths.each do |uri|
  failed_specs_from_log(bk_fetch(uri), only_files: options[:files]).each do |test_failure|
    unless failed_so_far.include?(test_failure)
      if options[:short]
        print " '#{test_failure}'"
      else
        puts test_failure
      end
      failed_so_far << test_failure
    end
  end
end

puts ""
