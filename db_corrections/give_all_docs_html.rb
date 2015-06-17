require_relative '../couch/wetten/dutch_law_couch'
require 'nokogiri'
require 'open-uri'
require 'base64'
BWB_TO_HTML = Nokogiri::XSLT(File.open('../xslt/bwb_to_html.xslt'))

couch = DutchLawCouch.new
# noinspection RubyStringKeysInHashInspection
def add_html(doc, str_xml)
  xml = Nokogiri::XML(str_xml.force_encoding('utf-8'))
  b64_html = Base64.encode64(BWB_TO_HTML.transform(xml).to_s.force_encoding('utf-8'))
  doc['_attachments'] = doc['_attachments'] || {}
  doc['_attachments']['data.htm'] = {
      'content_type' => 'text/html;charset=utf-8',
      'data' => b64_html
  }
  b64_html.bytesize
end

def get_xml(id)
  open("http://wetten.cloudant.com/bwb/#{id}/data.xml").read
end

i=0
couch.all_docs('bwb') do |docs|
  docs.each do |doc|
    str_xml = get_xml(doc['_id'])
    add_html(doc, str_xml)
    puts doc['_id']
    couch.add_and_maybe_flush doc
    i+=1
    if i%250==0
      couch.flush_cache
      puts ">#{i}"
    end
  end
end


