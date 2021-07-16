#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'mechanize'
require 'progress_bar'

DOWNLOAD_PATH = File.expand_path('./audiobooks')
TMP_EXTENSION = '.tmp'

def create_folder(directory)
  FileUtils.mkdir_p(directory) unless File.directory?(directory)
end

def client
  @client ||= Mechanize.new
end

def audiobooks
  response = client.get('https://iceportal.de/api1/rs/page/hoerbuecher')

  # extract titles
  json_data = JSON.parse(response.body)

  json_data['teaserGroups'].first['items'].map do |item|
    item['navigation']
  end
end

def download_audiobook(json)
  path = json['href']
  title = path.split('/').last
  directory = File.join(DOWNLOAD_PATH, title)
  tmp_dir = "#{directory}#{TMP_EXTENSION}"
  if Dir.exists?(directory)
    puts "\nAudiobook #{title} already exists"
    return
  end
  puts "\nDownloading audiobook: #{title}"

  chapter_response = client.get("https://iceportal.de/api1/rs/page/hoerbuecher/#{title}")

  # extract chapters
  json_data = JSON.parse(chapter_response.body)
  playlist = json_data['files']

  # extract download_paths for each chapter
  download_paths = playlist.map do |chapter|
    url = "https://iceportal.de/api1/rs/audiobooks/path#{chapter['path']}"
    response_download_path = client.get(url)

    JSON.parse(response_download_path.body)['path']
  end

  create_folder(tmp_dir)
  progress_bar = ProgressBar.new(download_paths.count)

  # download each track
  download_paths.each_with_index do |track, counter|
    progress_bar.increment!

    url = "https://iceportal.de#{track}"

    save_path = File.join(tmp_dir, "#{title}_#{counter + 1}.mp3")
    client.download(url, save_path)
  end
  File.rename(tmp_dir, directory)
end # download_audiobook

# MAIN

# download all audibooks
audiobooks.each do |book|
  download_audiobook(book)
end
