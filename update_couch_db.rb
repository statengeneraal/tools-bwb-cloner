require_relative 'couch_updater'

# This script syncs our CouchDB database against the government BWBIdList. Run daily.
CouchUpdater.new.start