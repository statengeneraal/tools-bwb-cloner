require 'open-uri'
require 'uri'
require 'base64'
require 'logger'
require 'nokogiri'
require 'json'
require_relative 'couch/wetten/cloudant_wetten'
require_relative 'overheid-bwb/bwb_list_parser'
require_relative 'overheid-bwb/bwb_download'

include BwbDownload

class CouchUpdater
  LAWLY_ROOT = 'http://wetten.lawly.nl/'

  def initialize
    @logger = Logger.new('couch_update.log')

    @couch = CloudantWetten.new
    @bytesize = 0
    @bulk=[]
    @expressions_added=0
    @new_expressions = []
    @metadata_changed = {}
    @disappeared = []
    @today = Date.today.strftime('%Y-%m-%d')
  end

  def start
    xml_source = download_metadata_dump

    # Get what's in OUR database
    rows_cloudant, prev_paths, _ = @couch.get_cloudant_entries

    # Parse government XML
    sax_handler = BwbListParser.new(prev_paths)
    parser = Nokogiri::XML::SAX::Parser.new(sax_handler)
    puts 'Parsing XML...'
    parser.parse xml_source
    puts 'XML parsed.'

    bwb_list = sax_handler.bwb_list

    # Find new expressions
    get_differences(rows_cloudant, bwb_list)

    puts "Found #{bwb_list[JsonConstants::LAW_LIST].length} expressions, of which #{@new_expressions.length} new, #{@metadata_changed.length} had metadata changed, #{@disappeared.length} disappeared"
    @logger.info "Found #{bwb_list[JsonConstants::LAW_LIST].length} expressions, of which #{@new_expressions.length} new, #{@metadata_changed.length} had metadata changed, #{@disappeared.length} disappeared"

    # Download new expressions and upload to CouchDB
    process_changes
  end

  # noinspection RubyStringKeysInHashInspection
  def set_as_new_expr_no_attach(doc)
    expression_id = "#{doc[JsonConstants::BWB_ID]}:#{doc[JsonConstants::DATE_LAST_MODIFIED]}"
    doc['@type'] = 'frbr:Expression'
    doc['frbr:realizationOf'] = doc[JsonConstants::BWB_ID]
    doc['foaf:page'] = "#{LAWLY_ROOT}bwb/#{expression_id}"
    doc['_id'] = expression_id
    doc['couchDbModificationDate'] = @today
    doc['displayKind'] = get_display_kind(doc)
    doc['addedToCouchDb'] = @today
    doc.delete('xml')
    # TODO add dcterms:tableOfContents, dcterms:publisher='KOOP'
    # TODO dcterm:seealso/sameas metalex id
  end

  # noinspection RubyStringKeysInHashInspection
  def add_original_xml(doc, b64_xml)
    doc['_attachments'] = doc['_attachments'] || {}
    doc['_attachments']['data.xml'] = {
        'content_type' => 'text/xml',
        'data' => b64_xml
    }
  end

  # noinspection RubyStringKeysInHashInspection
  def setup_doc_as_new_expression(doc, str_xml)
    set_as_new_expr_no_attach(doc)
    b64_xml = Base64.encode64(str_xml)
    add_original_xml(doc, b64_xml)
    puts "Adding bytesizes: #{(b64_xml.bytesize)/1024.0/1024.0} MB"
    b64_xml.bytesize
  end



  private

  # Download XML of given documents and upload the expressions to CouchDB
  def process_changes
    add_new_expressions
    process_changed_metadata
    puts 'Done.'
  end

  def process_changed_metadata
    changes_keys=[]
    @metadata_changed.each do |id, _|
      changes_keys << id
    end
    if changes_keys.length > 0
      set_new_metadata(changes_keys)
    end
  end

  def set_new_metadata(changes_keys)
    bulk=[]
    docs = get_all_docs('bwb', {keys: changes_keys})
    docs.each do |doc|
      doc['couchDbModificationDate'] = @today
      # Copy over attributes
      @metadata_changed[doc['_id']].each do |key, value|
        if value == '_delete'
          doc.delete(key)
        else
          doc[key] = value
        end
      end

      bulk << doc
    end
    bulk_write(bulk)
  end

  # noinspection RubyStringKeysInHashInspection
  def add_new_expressions
    @bytesize = 0
    @bulk = []
    @new_expressions.each do |doc|
      doc=doc.clone
      # Download (or skip) this document
      str_xml = get_gov_xml(doc[JsonConstants::BWB_ID])
      if str_xml
        puts str_xml
        doc_bytesize = setup_doc_as_new_expression(doc, str_xml)
        @bytesize += doc_bytesize
        @bulk << doc
        # Flush if array gets too big
        flush_if_too_big

        @expressions_added+=1
        if @expressions_added > 0 and @expressions_added % 10 == 0
          puts "Downloaded #{@expressions_added} new expressions."
        end
      end
    end

    #Flush remaining
    if @bulk.size > 0
      bulk_write(@bulk)
      @bytesize = 0
      @bulk.clear
    end
  end

  def get_gov_xml(bwb_id)
    url = "http://wetten.overheid.nl/xml.php?regelingID=#{bwb_id}"
    begin
      return open(url, :read_timeout => 30*60).read
    rescue Net::ReadTimeout
      @logger.error "ERROR: Could not download #{url}"
      @couch.add_to_blacklist(bwb_id)
    rescue Exception
      @logger.error "ERROR: Could not download #{url}"
    end
    nil
  end

# Flush documents in @bulk array if its size exceeds a certain size
  def flush_if_too_big(max_bulk_size=15)
    if @bytesize >= max_bulk_size*1024*1024 or @bulk.size >= 20 # Flush after some MB or 20 items
      bulk_write(@bulk)
      # puts "Flush #{bulk.size}"
      @bulk.clear
      @bytesize = 0
    end
  end

  def get_display_kind(doc)
    display_kind = nil
    if doc[JsonConstants::KIND]
      case doc[JsonConstants::KIND]
        when 'AMvB',
            'AMvB-BES',
            'beleidsregel',
            'circulaire',
            'circulaire-BES',
            'KB',
            'rijksKB',
            'rijkswet',
            'reglement',
            'verdrag',
            'wet',
            'wet-BES',
            'beleidsregel-BES',
            'ministeriele-regeling',
            'ministeriele-regeling-archiefselectielijst',
            'ministeriele-regeling-BES'
          display_kind = doc[JsonConstants::KIND].gsub('inisteriele', 'inisteriële').gsub('-', ' ').capitalize
        when 'pbo',
            'zbo'
          display_kind = doc[JsonConstants::KIND]
        else
          display_kind = doc[JsonConstants::KIND]
      end
    end
    display_kind
  end


# Find gaps between database and BwbIdList.xml
  def get_differences(rows_cloudant, bwb_list)
    existing_couch_ids={}

    # See if metadata has changed
    rows_cloudant.each do |row|
      evaluate_row_against_bwbidlist(bwb_list, row)
    end

    # Find new expressions
    rows_cloudant.each do |row|
      id = row['id']
      # if(id.start_with? 'BWBR0001827')
      #   puts 'uuuuh'
      # end
      existing_couch_ids[id] = true
      existing_couch_ids[id.gsub('/', ':')] = true
    end
    bwb_list[JsonConstants::LAW_LIST].each do |bwb_id, regeling_info|
      expression_id="#{bwb_id}:#{regeling_info[JsonConstants::DATE_LAST_MODIFIED]}"
      unless existing_couch_ids[expression_id] or @couch.is_blacklisted?(bwb_id)
        @logger.info "#{expression_id} was new."
        @new_expressions << regeling_info
      end
    end
  end


  def evaluate_row_against_bwbidlist(bwb_list, couch_row)
    id = couch_row['id']
    # if(id.start_with? 'BWBR0001827')
    #   puts 'uuuuh'
    # end
    bwb_id = couch_row['key']
    doc = couch_row['value']
    if bwb_list[JsonConstants::LAW_LIST][bwb_id]
      regeling_info = bwb_list[JsonConstants::LAW_LIST][bwb_id]

      date_last_modified=regeling_info[JsonConstants::DATE_LAST_MODIFIED]
      if date_last_modified == couch_row['value'][JsonConstants::DATE_LAST_MODIFIED]
        #Check if metadata is the same, still
        regeling_info.each do |key, value|
          unless key == 'displayTitle' or key == 'path'
            unless is_same(doc[key], value)
              changes = @metadata_changed[id]
              changes ||= {}
              changes[key] = value
              @metadata_changed[id] = changes
              break
            end
          end
        end
      end
      @metadata_changed
    else
      @disappeared << id
    end
  end



  def is_same(metadata1, metadata2)
    if metadata1 == metadata2
      same = true
    else
      if metadata1.is_a? Array # Order doesn't matter
        m1 = metadata1.uniq
        m1 = m1.sort_by do |array_item|
          if array_item.is_a? Comparable
            array_item
          else
            array_item.hash
          end
        end

        m2 = metadata2.uniq
        m2 = m2.sort_by do |array_item|
          if array_item.is_a? Comparable
            array_item
          else
            array_item.hash
          end
        end

        same = (m1 == m2)
      else
        same = false
      end
    end
    same
  end
end

class Expression
  attr_reader :bwb_id
  attr_reader :date
  attr_reader :id
  attr_reader :human_date

  def initialize(bwb_id, date)
    @bwb_id=bwb_id
    @date=date
    @id = "#{bwb_id}:#{date}"

    last_modified_match = date.match(/([0-9]+)-([0-9]+)-([0-9]+)/)
    @human_date = nil
    if last_modified_match
      @human_date = "#{last_modified_match[3]}-#{last_modified_match[2]}-#{last_modified_match[1]}"
    end
  end
end

