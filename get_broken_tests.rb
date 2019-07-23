require 'pry'
require 'json'
require 'net/http'

BK_TOKEN = ENV['BK_TOKEN'].freeze

def bk_fetch_api_paginate(uri, auto_paginate: false, per_page: 100)
  page = 1
  Enumerator.new do |enum|
    data = nil
    while data.nil? || data.size > 0
      data = bk_fetch(uri, page: page, per_page: per_page)
      data.each { |d| enum << d }
      page += 1
    end
  end
end

def bk_fetch(uri, page: 1, per_page: 100)
  res = Net::HTTP.get_response(URI.parse("#{uri}?access_token=#{BK_TOKEN}&per_page=#{per_page}&page=#{page}"))
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
  examples = content.lines.flat_map { |l| l.match(/rspec (\'*\.\/spec.*).*/)&.captures }.compact.map { |l| l[0..(l.index('#') || 0)-1].strip }.map { |l| l.gsub(/\A'/, '').gsub(/'\z/, '') }

  if only_files
    examples.map { |e| e.slice(0, e.rindex('.rb')+3) }
  else
    examples
  end
end

def failed_specs(log_file_paths)
  Enumerator.new do |y|
    log_file_paths.each do |uri|
      failed_specs_from_log(bk_fetch(uri)).each do |test_failure|
        y << test_failure
      end
    end
  end
end

def file_only_for_failure(test_failure)
  test_failure.slice(0, test_failure.rindex('.rb')+3)
end

class OnlyFailureProcessor
  def process(enum)
    enum.map(&method(:file_only_for_failure))
  end
end

class ShortenForBashProcessor
  def process(enum)
    enum.group_by(&method(:file_only_for_failure)).flat_map do |file, test_failures|
      if test_failures.size > 1
        only_test_part = test_failures.map do |test_failure|
          test_failure[test_failure.rindex('.rb')+3..-1]
        end
        regular_examples = only_test_part.reject { |t| t.start_with?('[') }
        regular_examples_short = "#{file}{#{regular_examples.join(',')}}" if regular_examples.any?
        shared_examples = only_test_part.select { |t| t.start_with?('[') }.map { |t| "'#{file}#{t}'" }
        [*regular_examples_short, *shared_examples]
      else
        test_failures
      end
    end
  end
end

class UniquenessProcessor
  def process(enum)
    enum.reduce([]) do |seen_failures, test_failure|
      unless seen_failures.include?(test_failure)
        seen_failures << test_failure
      end
      seen_failures
    end
  end
end

class PrintingProcessor
  def initialize(short: false)
    @short = short
  end

  def process(enum)
    enum.each do |test_failure|
      if @short
        print " '#{test_failure}'"
      else
        puts test_failure
      end
    end
    enum
  end
end

require 'optparse'

options = { files: false, short: false, bash: true }
opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{__FILE__} [options] [ZP_BUILD_ID]"

  opts.on("-f", "--files", "Only print files") do |o|
    options[:files] = o
  end

  opts.on('-b', '--bash', 'Shorten for bash') do |o|
    options[:bash] = o
  end

  opts.on('-s', '--short', 'Shorten output for rspec') do |o|
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

pipeline = []
pipeline << OnlyFailureProcessor.new if options[:files]
pipeline << ShortenForBashProcessor.new if options[:bash]
pipeline << UniquenessProcessor.new
pipeline << PrintingProcessor.new(short: options[:short])
pipeline.compact!

current_enum = failed_specs(log_file_paths)
pipeline.each do |pipeline|
  current_enum = pipeline.process(current_enum)
end

puts ""