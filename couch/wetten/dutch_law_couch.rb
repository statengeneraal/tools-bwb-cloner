require 'couch'
require_relative 'json_constants'

include JSON

class DutchLawCouch < Couch::Server
  attr_accessor :cache
  attr_accessor :bytesize

  def initialize
    super(
        ENV['COUCH_URL_WETTEN'],
        {
            name: ENV['COUCH_USER_WETTEN'],
            password: ENV['COUCH_PASSWORD_WETTEN']
        }
    )
    @cache=[]
    @bytesize = 0
  end

  # Flush documents in @bulk array if its size exceeds a certain size
  def flush_if_too_big(max_bulk_size=1)
    # puts "#{@bytesize/1024/1024}MB"
    if @bytesize >= max_bulk_size*1024*1024 or @cache.size >= 20 # Flush after some MB or 20 items
      bulk_write(@cache)
      # puts "Flush #{bulk.size}"
      @cache.clear
      @bytesize = 0
    end
  end


  # Returns all expressions for the BWB documents described by the given expressions. E.g. ['BWBxxx:2012-12-12'] would
  # return {'BWBxxx': [<all expressions for BWBxxx in our database>]}
  def get_realization_map(expressions)
    # Get BWBIDs
    bwb_ids = Set.new
    expressions.each do |doc|
      bwb_ids << doc[BWB_ID]
    end
    bwb_ids = bwb_ids.to_a

    # Gather expressions for given BWBIDs
    expression_map = {}
    rows_for_view('bwb', 'RegelingInfo', 'expressionsForBwbId', 750, {keys: bwb_ids}) do |rows|
      rows.each do |row|
        bwbid=row['key']
        set = expression_map[bwbid] || Set.new
        set << row['id']
        expression_map[bwbid] = set
      end
    end
    expressions.each do |doc|
      bwbid=doc[BWB_ID]
      set = expression_map[bwbid] || Set.new
      set << doc['_id']
    end

    # Return
    expression_map
  end

  def bulk_write(docs, max_post_size: 15)
    post_bulk_throttled('bwb', docs, max_size_mb: max_post_size) do |res|
      if res.code >= '200' and res.code < '300'
        resp = JSON.parse res.body
        error_count=0
        resp.each do |res_doc|
          if res_doc['error']
            error_count += 1
            puts "#{res_doc['id']}: #{res_doc['error']}"
            puts "#{res_doc['reason']}"
          end
        end
      end
    end
  end

  # Get metadata of documents currently in CouchDB, along with a mapping of BWBIDs to paths and a list of docs that have its path field set wrongly
  def get_our_entries
    paths = {}
    wrong_paths = []
    our_rows = []
    rows_for_view('bwb', 'RegelingInfo', 'allExpressions', 750) do |row_slice|
      row_slice.each do |row|
        our_rows << row
        bwb_id = row['key']
        if row['value']['path']
          if paths[bwb_id]
            unless paths[bwb_id] == row['value']['path']
              puts "WARNING: #{row['id']} had a different path than #{paths[bwb_id]} (namely #{row['value']['path']})"
              wrong_paths << row
            end
          else
            paths[bwb_id] = row['value']['path']
          end
        else
          # puts "WARNING: #{row['id']} did not have a path set"
          wrong_paths << row
        end
      end
    end
    puts "Found #{our_rows.length} expressions in our own database"
    return our_rows, paths, wrong_paths
  end

  def is_blacklisted?(bwb_id)
    if head("/blacklist/#{bwb_id}").code == '200'
      url = "http://wetten.overheid.nl/xml.php?regelingID=#{bwb_id}"
      puts "Skipping #{bwb_id} because it took too long to download before (at #{url})"
      true
    else
      false
    end
  end

  def add_to_blacklist(id)
    put("/blacklist/#{id}", {_id: id}.to_json)
    puts "Added #{id} to blacklist"
  end

  def flush_cache
    if @cache.size > 0
      bulk_write(@cache)
      @bytesize = 0
      @cache.clear
    end
  end

  def add_and_maybe_flush(doc)
    cache << doc
    flush_if_too_big
  end
end