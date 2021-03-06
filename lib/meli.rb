# encoding: UTF-8

require 'rubygems'
require 'net/http'
require 'net/https'
require 'json'
require 'uri'
require 'yaml'

class Meli
    attr_accessor :access_token, :refresh_token
    attr_reader :secret, :app_id, :https

    config = YAML.load_file(File.expand_path(File.dirname(__FILE__) + "/config.yml"))
    SDK_VERSION = config["config"]["sdk_version"]
    API_ROOT_URL = config["config"]["api_root_url"]
    AUTH_URL = config["config"]["auth_url"]
    OAUTH_URL = config["config"]["oauth_url"]

    #constructor
    def initialize(app_id = nil, secret = nil, access_token = nil, refresh_token = nil)
        @access_token = access_token
        @refresh_token = refresh_token
        @app_id = app_id
        @secret = secret
        api_url = URI.parse API_ROOT_URL
        @https = Net::HTTP.new(api_url.host, api_url.port)
        @https.use_ssl = true
        @https.verify_mode = OpenSSL::SSL::VERIFY_PEER
        @https.ssl_version = :TLSv1
    end

    #AUTH METHODS
    def auth_url(redirect_URI)
        params = {:client_id  => @app_id, :response_type => 'code', :redirect_uri => redirect_URI}
        url = "#{AUTH_URL}?#{to_url_params(params)}"
    end

    def auth(grant_type, params = {})
        params.merge!({
            :grant_type => grant_type,
            :client_id => @app_id,
            :client_secret => @secret,
        })

        uri = make_path(OAUTH_URL, params)

        req = Net::HTTP::Post.new(uri.path)
        req['Accept'] = 'application/json'
        req['User-Agent'] = SDK_VERSION
        req['Content-Type'] = "application/x-www-form-urlencoded"
        req.set_form_data(params)
        response = @https.request(req)

        case response
        when Net::HTTPSuccess
            response_info = JSON.parse response.body

            #convert hash keys to symbol
            response_info = Hash[response_info.map{ |k, v| [k.to_sym, v] }]

            @access_token = response_info[:access_token]

            if response_info.has_key?(:refresh_token)
                @refresh_token = response_info[:refresh_token]
            end

            {
                :access_token => @access_token,
                :refresh_token => @refresh_token,
                :expires_in => response_info[:refresh_token],
                :date => response['date'],
                :id => response_info[:id]
            }
        else
            # response code isn't a 200; raise an exception
            response.error!
        end
    end

    def authorize(code, redirect_URI)
        auth 'authorization_code', {:code => code, :redirect_uri => redirect_URI}
    end

    def get_refresh_token()
        if !@refresh_token.nil? and !@refresh_token.empty?
            auth 'refresh_token', {:refresh_token => @refresh_token}
        else
            raise "Offline-Access is not allowed."
        end
    end

    #REQUEST METHODS
    def execute(req)
        req['Accept'] = 'application/json'
        req['User-Agent'] = SDK_VERSION
        req['Content-Type'] = 'application/json'
        response = @https.request(req)
    end

    def get(path, params = {})
        uri = make_path(path, params)
        req = Net::HTTP::Get.new("#{uri.path}?#{uri.query}")
        execute req
    end

    def post(path, body, params = {})
        uri = make_path(path, params)
        req = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
        req.set_form_data(params)
        req.body = body.to_json unless body.nil?
        execute req
    end

    def put(path, body, params = {})
        uri = make_path(path, params)
        req = Net::HTTP::Put.new("#{uri.path}?#{uri.query}")
        req.set_form_data(params)
        req.body = body.to_json unless body.nil?
        execute req
    end

    def delete(path, params = {})
        uri = make_path(path, params)
        req = Net::HTTP::Delete.new("#{uri.path}?#{uri.query}")
        execute req
    end

    def options(path, params = {})
        uri = make_path(path, params)
        req = Net::HTTP::Options.new("#{uri.path}?#{uri.query}")
        execute req
    end

private
    def to_url_params(params)
      URI.escape(params.collect{|k,v| "#{k}=#{v}"}.join('&'))
    end

    def make_path(path, params = {})
        # Making Path and add a leading / if not exist
        path = "/#{path}" unless path =~ /^\//
        path = "#{API_ROOT_URL}#{path}"
        
        path = "#{path}?#{to_url_params(params)}" if params.keys.size > 0
        uri = URI.parse path
    end

end  #class
