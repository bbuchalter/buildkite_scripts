require 'json'
require 'net/http'

BK_TOKEN = ENV['BK_TOKEN'].freeze

def bk_fetch(uri, page: 1, per_page: 100)
  res = Net::HTTP.get_response(URI.parse("#{uri}?access_token=#{BK_TOKEN}&per_page=#{per_page}&page=#{page}"))
  if res['Content-Type']&.include?('application/json')
    JSON.parse(res.body)
  elsif res['Content-Type'] == 'text/plain; charset=utf-8'
    res.body.force_encoding("UTF-8")
  else
    res.body
  end
end

def fetch_build(build_id)
  bk_fetch("https://api.buildkite.com/v2/organizations/gusto/pipelines/zenpayroll/builds/#{build_id}/")
end

pipeline = ARGV[0]
build_id = ARGV[1].to_i

if pipeline.nil? || build_id.nil? || build_id == 0
  puts "Usage: #{$0} $BUILDKITE_PIPELINE_NAME $BUILD_NUMBER"
  exit 1
end

build = fetch_build(build_id)
jobs = build.fetch('jobs')
jobs.each do |job|
  raw_log_url = job['raw_log_url']
  next unless raw_log_url

  job_id = job.fetch('id')

  filename = job_id + ".output.log"
  path = File.join(Dir.pwd, 'tmp', build_id.to_s, job_id)
  destination = File.join(path, filename)
  FileUtils.mkdir_p path
  puts destination
  job_log = bk_fetch(raw_log_url)
  File.write(destination, job_log)
end
