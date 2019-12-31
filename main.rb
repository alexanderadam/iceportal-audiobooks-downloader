#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'mechanize'

def create_folder(directory)
  FileUtils.mkdir_p(directory) unless File.directory?(directory)
end # create_folder

def requests
  @browser ||= Mechanize.new
end

def get_all_audiobooks
  audiobooks = []

  url = 'https://iceportal.de/api1/rs/page/hoerbuecher'
  response = requests.get(url)

  # extract titles
  json_data = JSON.parse(response.body)
  items = json_data['teaserGroup']['items']

  items.each do |item|
    name = item['navigation']['href']
    audiobooks.append(name)
  end

  audiobooks
end # get_all_audiobooks

def download_audiobook(path)
  title = path.split('/').last
  puts("Downloading audiobook: #{title}")

  url = "https://iceportal.de/api1/rs/page/hoerbuecher/#{title}"
  chapter_response = requests.get(url)

  # extract chapters
  json_data = JSON.parse(chapter_response.body)
  playlist = json_data['files']

  # extract download_path for each chapter
  download_path = []
  playlist.each do |chapter|
    chapter_path = chapter['path']

    url = "https://iceportal.de/api1/rs/audiobooks/path#{chapter_path}"
    response_download_path = requests.get(url)

    path = JSON.parse(response_download_path.body)['path']
    download_path.append(path)
  end

  create_folder("./audiobooks/#{title}")

  # download each track
  download_path.each_with_index do |track, counter|
    puts("#{counter + 1}/#{download_path.length}")

    url = "https://iceportal.de#{track}"

    save_path = "audiobooks/#{title}/#{title}_#{counter + 1}.mp3"
    requests.download(url, save_path)
  end
end # download_audiobook

# MAIN
# extract all audiobooks
audiobooks = get_all_audiobooks
create_folder('./audiobooks')

# download all audibooks
audiobooks.each do |book|
  download_audiobook(book)
end
