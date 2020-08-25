require 'dotenv/load'
require 'kraken_ruby_client'
require 'tty-table'

class Chewie
  attr_reader :client

  def initialize
    @client = Kraken::Client.new(api_key: ENV['KRAKEN_API_KEY'], api_secret: ENV['KRAKEN_API_SECRET'])
    @vwaps = {}
    @vwaps_retrieval_at = {}
  end

  # 15 min interval, last 24h
  def retrieve_vwaps(pair)
    now = Time.now.to_i

    # don't call again in the same 5 seconds:
    return @vwaps[pair] if (now - @vwaps_retrieval_at[pair].to_i) <= 5

    response = @client.ohlc(pair, interval: 15, since: now - (24 * 60 * 60))
    raise(StandardError, response['error']) if response['error'].any?

    @vwaps[pair] = response['result'].first.last.map { |x| x[5].to_f }
    @vwaps_retrieval_at[pair] = now
    @vwaps[pair]
  end

  def avg_24(pair)
    vwaps = retrieve_vwaps(pair).reject(&:zero?)
    vwaps.sum.fdiv(vwaps.length)
  end

  def avg_23(pair)
    vwaps = retrieve_vwaps(pair)[4..-1].reject(&:zero?)
    vwaps.sum.fdiv(vwaps.length)
  end

  def rate_24(pair)
    vwaps = retrieve_vwaps(pair).reject(&:zero?)
    (vwaps.last - vwaps.first) / vwaps.first
  end

  def rate_23(pair)
    vwaps = retrieve_vwaps(pair)[4..-1].reject(&:zero?)
    (vwaps.last - vwaps.first) / vwaps.first
  end

  def chew
    pairs = client.asset_pairs['result'].keys.select { |pair| pair.end_with?('XBT') }
    puts "Querying #{pairs}"

    @half_eaten_mass = pairs.each_with_index.map do |pair, i|
      sleep 6 # history calls count 2 points
      puts "#{(i + 1).to_s.rjust(3, ' ')}/#{pairs.length}…"
      {
        pair: pair,
        avg_24: avg_24(pair),
        avg_23: avg_23(pair),
        rate_24: rate_24(pair),
        rate_23: rate_23(pair),
        diff: rate_23(pair) - rate_24(pair)
      }
    end
  end

  def sell
    response = @client.balance
    raise(StandardError, response['error']) if response['error'].any?

    balance = response['result']
    pairs_wanna_sell = @half_eaten_mass.select { |row| row[:diff] < -0.049 }.map { |row| row[:pair] }
    return if pairs_wanna_sell.empty?

    positions_can_sell = balance.keys - ['XXBT']

    pairs_wanna_sell.each do |pair|
      position_will_sell = positions_can_sell.find { |symbol| pair.include?(symbol) }

      next unless position_will_sell

      volume = balance[position_will_sell] # everything we have
      # @client.add_order(pair: pair, type: 'sell', ordertype: 'market', volume: volume)
      puts "Would sell #{pair} at #{volume}"
    end
  end

  def buy
    balance_response = @client.balance
    raise(StandardError, balance_response['error']) if balance_response['error'].any?

    pairs_wanna_buy = @half_eaten_mass.select { |row| row[:diff] > 0.049 }.map { |row| row[:pair] }
    return if pairs_wanna_buy.empty?

    xbt_per_trade = (balance_response['result']['XXBT'].to_f / 2) / pairs_wanna_buy.length

    ticker_response = @client.ticker(pairs_wanna_buy.join(','))
    raise(StandardError, ticker_response['error']) if ticker_response['error'].any?

    pairs_wanna_buy.each do |pair|
      last_price = ticker_response['result'][pair]['c'].first.to_f
      volume = xbt_per_trade / last_price
      # @client.add_order(pair: pair, type: 'buy', ordertype: 'market', volume: volume)
      puts "Would buy #{pair} at #{volume}"
    end
  end

  def display_table
    table = TTY::Table.new(
      header: @half_eaten_mass.first.keys,
      rows: @half_eaten_mass.map(&:values)
    )

    table.render do |renderer|
      renderer.filter = proc do |val, row_index, col_index|
        if row_index.positive?
          case col_index
          when 1, 2
            val.to_f.round(8).to_s
          when 3, 4
            "#{(val.to_f * 100).round(2)}%"
          when 5
            v = "#{(val.to_f * 100).round(2)}%"
            v[0] == '-' ? Pastel.new.red(v) : Pastel.new.green(v)
          else
            val
          end
        else
          val
        end
      end
    end
  end
end

chewie = Chewie.new
chewie.chew
puts chewie.display_table
chewie.sell
chewie.buy
