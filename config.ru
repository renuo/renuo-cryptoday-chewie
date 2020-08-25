require 'dotenv/load'
require 'json'
require 'kraken_ruby_client'

app = Proc.new do |_env|
  client = Kraken::Client.new(api_key: ENV['KRAKEN_API_KEY'], api_secret: ENV['KRAKEN_API_SECRET'])
  balance = client.balance['result']

  [200, { 'Content-Type' => 'application/json' }, [balance.to_json]]
end

run app
