#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'mechanize'
require 'ruby-progressbar'
require 'mp3info'

DOWNLOAD_PATH = File.expand_path('./audiobooks')
TMP_EXTENSION = '.tmp'
GENRES = {
  'podcast' => 186,
  'audioBook' => 183
}

# Begin of monkey patch to avoid issue https://github.com/moumar/ruby-mp3info/issues/67
Mp3Info.class_eval do
  ### reads through @io from current pos until it finds a valid MPEG header
  ### returns the MPEG header as FixNum
  def find_next_frame
    # @io will now be sitting at the best guess for where the MPEG frame is.
    # It should be at byte 0 when there's no id3v2 tag.
    # It should be at the end of the id3v2 tag or the zero padding if there
    #   is a id3v2 tag.
    #dummyproof = @io.stat.size - @io.pos => WAS TOO MUCH

    dummyproof = [ @io_size - @io.pos, 39_000_000 ].min
    dummyproof.times do |i|
      if @io.getbyte == 0xff
        data = @io.read(3)
        raise Mp3InfoEOFError if @io.eof?
        head = 0xff000000 + (data.getbyte(0) << 16) + (data.getbyte(1) << 8) + data.getbyte(2)
        begin
          return Mp3Info.get_frames_infos(head)
        rescue Mp3InfoInternalError
          @io.seek(-3, IO::SEEK_CUR)
        end
      end
    end
    if @io.eof?
      raise Mp3InfoEOFError
    else
      raise Mp3InfoError, "cannot find a valid frame after reading #{dummyproof} bytes"
    end
  end
end
# end of monkey patch


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

def update_id3_info(file_path, book_json, chapter_json, cover_path)
  Mp3Info.open(file_path) do |mp3|
    mp3.tag.album = book_json['title']
    mp3.tag.artist = book_json['author']
    mp3.tag.title = chapter_json['title']
    mp3.tag.comments = chapter_json['description']
    mp3.tag.tracknum = chapter_json['serialNumber']
    mp3.tag.genre = GENRES[book_json['contentType']] || raise("Unknown genre #{book_json['contentType']}")
    mp3.tag.year = book_json['releaseYear']
    mp3.tag2.add_picture(File.read(cover_path, mode: 'rb'))
  end
rescue => e
  puts "Unable to update ID3 metadata for #{File.basename(file_path)} #{e.class}: #{e.message}"
end

def download_track(slug, chapter_json, tmp_dir, track_no)
  url = "https://iceportal.de/api1/rs/audiobooks/path#{chapter_json['path']}"
  response_download_path = client.get(url)
  url = "https://iceportal.de#{JSON.parse(response_download_path.body)['path']}"

  file_path = File.join(tmp_dir, "#{slug}_#{track_no}.mp3")
  client.download(url, file_path)
  file_path
end

def download_audiobook(base_json)
  slug = base_json['href'].split('/').last
  directory = File.join(DOWNLOAD_PATH, slug)
  tmp_dir = "#{directory}#{TMP_EXTENSION}"
  if Dir.exists?(directory)
    puts "\nAudiobook #{slug} already exists"
    return
  end

  chapter_response = client.get("https://iceportal.de/api1/rs/page/hoerbuecher/#{slug}")
  create_folder(tmp_dir)

  # extract chapters
  book_json = JSON.parse(chapter_response.body)

  progress_bar= ProgressBar.create(format: "%a %b\e[93m\u{15E7}\e[0m%i %p%% #{book_json['title']}",
                                   progress_mark: ' ',
                                   remainder_mark: "\u{FF65}",
                                   total: book_json['files'].count)
  cover_image_url = "https://iceportal.de/#{book_json['picture']['src']}"
  cover_path = File.join(tmp_dir, "cover.#{cover_image_url.split('.').last || 'jpg'}")
  client.download(cover_image_url, cover_path)
  rjust_params = [book_json['files'].count.to_s.size, '0']

  # extract download_paths for each chapter
  book_json['files'].each do |chapter_json|
    track_no = chapter_json['serialNumber'].to_s.rjust(*rjust_params)
    file_path = download_track(slug, chapter_json, tmp_dir, track_no)
    update_id3_info(file_path, book_json, chapter_json, cover_path)
    progress_bar.increment
  end
  File.rename(tmp_dir, directory)
end # download_audiobook

# MAIN

# download all audibooks
audiobooks.each do |base_json|
  download_audiobook(base_json)
end
