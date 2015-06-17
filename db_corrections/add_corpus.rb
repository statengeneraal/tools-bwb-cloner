require_relative '../couch/wetten/dutch_law_couch'

couch=DutchLawCouch.new
couch.all_docs('bwb') do |doc|
  if (!doc['corpus']) && doc['bwbId']
    doc['corpus'] = 'BWB'
    couch.add_and_maybe_flush(doc)
  end
end
couch.flush_cache
