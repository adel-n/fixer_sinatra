require 'sinatra'
require "sinatra/namespace"
require'mongoid'

Mongoid.load! "mongoid.config"

module FixerRates
	require "net/http"
	require "open-uri"

	def send_request_to_fixer(uri)
		retry_count = 3
		begin
			http = Net::HTTP.new(uri.host, uri.port)
			request = Net::HTTP::Get.new(uri.request_uri)
			response = http.request(request)
			JSON.parse(response.body)
		rescue Timeout::Error, Net::HTTPBadResponse, Net::HTTPUnauthorized, Net::ProtocolError => e
			if retry_count > 0
				retry_count -= 1
				sleep 5
				retry
			else
				raise
			end
		end					
	end

	def fixer_rates_per_date(date)
		uri = URI.parse("http://data.fixer.io/api/#{date}?access_key=#{api_key}")
		result = send_request_to_fixer(uri)
		if result["success"]
			create_fixer_rate(result)
			p result
		else
			p result
		end
	end

	def create_fixer_rate(result)
		Rate.create!(base_currency: result["base"], rates: result["rates"].as_json, date: result["date"])
	end

	private

	def api_key
		api_key = "83ff363fb12a3b4f699d14b8853988ef"
	end
end

class Rate
	extend FixerRates
  include Mongoid::Document

  field :base_currency, type: String
  field :date, type: String
  field :rates, type: Hash

  validates :base_currency, presence: true
  validates :date, presence: true
  validates :rates, presence: true

  index({ rates: 'text' })

  def self.get_fixer_rates(from, to, base, other)
		response = []
		while from <= to 
			exchange_rate = self.check_fixer_rates(from, base, other)
			if exchange_rate.present?
				response << exchange_rate
			else
				fixer_rates_per_date(from)
				response << self.check_fixer_rates(from, base, other)
			end	
			from += 1.days
		end	
		response
	end

	def self.check_fixer_rates(date, base, other)
		rate = Rate.where(date: "#{date}", base_currency: "#{base}")
		if rate.present?
			rr = rate.first 
			rate_hash = {}
			rate_hash["date"] = rr["date"]
			rate_hash["base"] = rr["base_currency"]
			rate_hash["rate"] = {other => rr["rates"][other]}
			rate_hash
		end	
	end
end

namespace '/api/v1' do
  before do
    content_type 'application/json'
  end

  get '/get_exchange_rates' do
  	from_date = params[:from]
  	to_date = params[:to]
  	base_currency = params[:base]
  	other_currency = params[:other]
    response = Rate.get_fixer_rates(from_date.to_date, to_date.to_date, base_currency, other_currency)
		response.to_json
  end
end



