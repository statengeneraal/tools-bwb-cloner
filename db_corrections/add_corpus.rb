require_relative '../couch/wetten/cloudant_wetten'
require_relative '../couch/wetten/cloudant_lawly_bwb'

couch=CloudantWetten.new
couch.for_all_docs('bwb') do |doc|
  if (!doc['corpus']) && doc['bwbId']
    doc['corpus'] = 'BWB'
    couch.add_and_maybe_flush(doc)
  end
end
couch.flush_cache

couch=CloudantLawlyBwb.new
couch.for_all_docs('bwb') do |doc|
  if (!doc['corpus']) && doc['bwbId']
    doc['corpus'] = 'BWB'
    couch.add_and_maybe_flush(doc)
  end
end
couch.flush_cache