ENV['RACK_ENV'] = 'test'

require 'rack/test'
require_relative '../app'
require_relative 'support/running_server'

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.before { Center.reset! }
  config.before { header 'Host', '127.0.0.1' }
end
