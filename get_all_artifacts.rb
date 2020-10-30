require 'json'
require 'net/http'
require 'open-uri'

BK_TOKEN = ENV['BK_TOKEN'].freeze

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

build_id = ARGV[0]&.to_i

if build_id.nil?
  puts "Missing ZP_BUILD_ID"
  exit 1
end

build = fetch_build(build_id)
jobs = build.fetch('jobs')
jobs.each do |job|
  artifacts_url = job['artifacts_url']
  next unless artifacts_url

  job_id = job.fetch('id')

  bk_fetch(artifacts_url).each do |artifact|
    filename = artifact.fetch('filename')
    path = File.join(Dir.pwd, 'tmp', build_id.to_s, job_id)
    destination = File.join(path, filename)
    FileUtils.mkdir_p path
    puts destination

    download_url = artifact.fetch('download_url')
    downloads = bk_fetch(download_url)
    downloads.each do |download|
      download_url = download[1]
      IO.copy_stream(URI.open(download_url), destination)
    end
  end
end
