require_relative '../couch'
require_relative 'json_constants'
require_relative '../secret'

include JSON
include Secret

class CloudantLawlyBwb < Couch::Server
  def initialize
    super(
        "#{LAWLY_NAME}.cloudant.com", '80',
        {
            name: LAWLY_NAME,
            password: LAWLY_PASSWORD
        }
    )
  end


end