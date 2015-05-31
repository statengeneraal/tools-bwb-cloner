require 'open-uri'
require 'uri'
require 'logger'
require 'zip'
require 'json'

module BwbDownload
  # Get government XML; BwbIdList. This list contains metadata for all laws currently in the government CMS.
  def download_metadata_dump
    puts 'Downloading XML'
    zipped_file = open('http://wetten.overheid.nl/BWBIdService/BWBIdList.xml.zip')
    xml_source = nil
    Zip::File.open(zipped_file) do |zip|
      xml_source = zip.read('BWBIdList.xml').force_encoding('UTF-8')
    end
    if xml_source == nil
      err = 'Could not read metadata XML dump'
      @logger.error err
      raise err
    end

    xml_source
  end
end