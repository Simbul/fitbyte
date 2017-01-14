require "fitbyte/base"
require "fitbyte/activities"
require "fitbyte/heart_rate"
require "fitbyte/goals"
require "fitbyte/alarms"
require "fitbyte/body"
require "fitbyte/devices"
require "fitbyte/food"
require "fitbyte/friends"
require "fitbyte/sleep"
require "fitbyte/user"
require "fitbyte/water"

module Fitbyte
  class Client
    attr_accessor :api_version, :unit_system, :locale, :scope, :snake_case, :symbolize_keys, :grant_type
    attr_reader   :user_id

    def initialize(opts)
      missing_args = [:client_id, :client_secret] - opts.keys
      raise Fitbyte::InvalidArgumentError, "Required arguments: #{missing_args.join(', ')}" if missing_args.size > 0

      if opts[:grant_type] && !['auth_code', 'implicit'].include?(opts[:grant_type])
        raise Fitbyte::InvalidArgumentError, "Unsupported grant_type '#{opts[:grant_type]}': please use 'auth_code' or 'implicit'"
      end

      %w(client_id client_secret redirect_uri site_url authorize_url token_url
      unit_system locale scope api_version snake_case symbolize_keys grant_type).each do |attr|
        instance_variable_set("@#{attr}", (opts[attr.to_sym] || Fitbyte.send(attr)))
      end

      @client = OAuth2::Client.new(@client_id, @client_secret, site: @site_url,
                                   authorize_url: @authorize_url, token_url: @token_url)

      if grant_type == 'auth_code'
        restore_token(opts[:refresh_token]) if opts[:refresh_token]
      elsif grant_type == 'implicit'
        if opts[:access_token] && opts[:user_id]
          init_token(opts[:access_token], opts[:user_id])
        else
          raise Fitbyte::InvalidArgumentError, "Implicit grant type needs :access_token and :user_id options to be passed in"
        end
      end
    end

    def auth_page_link
      if grant_type == 'auth_code'
        @client.auth_code.authorize_url(redirect_uri: @redirect_uri, scope: @scope)
      elsif grant_type == 'implicit'
        @client.implicit.authorize_url(redirect_uri: @redirect_uri, scope: @scope)
      end
    end

    def get_token(auth_code)
      @token = @client.auth_code.get_token(auth_code, redirect_uri: @redirect_uri, headers: auth_header)
      @user_id = @token.params["user_id"]
      return @token
    end

    def restore_token(refresh_token)
      @token = OAuth2::AccessToken.from_hash(@client, refresh_token: refresh_token).refresh!(headers: auth_header)
      @user_id = @token.params["user_id"]
      return @token
    end

    def init_token(access_token, user_id)
      @token = OAuth2::AccessToken.new(@client, access_token, 'user_id' => user_id)
      @user_id = @token.params["user_id"]
      return @token
    end

    def token
      @token.expired? ? refresh_token : @token
    end

    def refresh_token
      @token = @token.refresh!(headers: auth_header)
    end

    def auth_header
      {"Authorization" => ("Basic " + Base64.encode64(@client_id + ":" + @client_secret))}
    end

    def request_headers
      {
        "User-Agent" => "fitbyte-#{Fitbyte::VERSION} gem (#{Fitbyte::REPO_URL})",
        "Accept-Language" => @unit_system,
        "Accept-Locale" => @locale
      }
    end

    def get(path, opts={})
      response = token.get(("#{@api_version}/" + path), headers: request_headers).response
      object = MultiJson.load(response.body) unless response.status == 204
      process_keys!(object, opts)
    end

    def post(path, opts={})
      response = token.post(("#{@api_version}/" + path), body: deep_keys_to_camel_case!(opts), headers: request_headers).response
      object = MultiJson.load(response.body) unless response.status == 204
      process_keys!(object, opts)
    end

    def delete(path, opts={})
      response = token.delete(("#{@api_version}/" + path), headers: request_headers).response
      object = MultiJson.load(response.body) unless response.status == 204
      process_keys!(object, opts)
    end

    def process_keys!(object, opts={})
      deep_keys_to_snake_case!(object) if (opts[:snake_case] || snake_case)
      deep_symbolize_keys!(object) if (opts[:symbolize_keys] || symbolize_keys)
      return object
    end
  end
end
