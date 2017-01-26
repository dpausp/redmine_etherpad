require 'redmine'
require 'uri'
require 'net/http'
require 'json'
require 'time'
require 'date'
require 'pry'


def hash_to_querystring(hash)
  hash.keys.inject('') do |query_string, key|
    query_string << '&' unless key == hash.keys.first
    query_string << "#{URI.encode(key.to_s)}=#{URI.encode(hash[key].to_s)}"
  end
end


def etherpad_request(http, uri, endpoint, params)
  res = http.post((uri.path.nil? ? '' : uri.path) + endpoint, hash_to_querystring(params))
  JSON.parse(res.body)
end


def build_options(conf, params)
    # Defaults from configuration.
  # TODO: everything except height and width is ignored for now
  options = {
    'showControls' => conf.fetch('showControls', true),
    'showChat' => conf.fetch('showChat', true),
    'showLineNumbers' => conf.fetch('showLineNumbers', false),
    'useMonospaceFont' => conf.fetch('useMonospaceFont', false),
    'noColors' => conf.fetch('noColors', false),
    'width' => conf.fetch('width', '100%'),
    'height' => conf.fetch('height', '600px'),
  }
  # Override defaults with given arguments.
  for param in params
    key, val = param.strip().split("=")
    unless controls.has_key?(key)
      raise "#{key} not a recognized parameter."
    else
      defaults[key] = val
    end
  end
  options
end


Redmine::Plugin.register :redmine_etherpad do
  name 'Redmine Etherpad (lite) plugin'
  author 'Tobias Stenzel'
  description 'Provides an etherpad macro for embedding pads with Redmine auth integration (more features will follow...)'
  version '0.0'
  url 'https://github.com/dpausp/redmine_etherpad'
  author_url 'https://github.com/dpausp'

  Redmine::WikiFormatting::Macros.register do
    desc "Embed etherpad with auth"
    macro :etherpad do |obj, args|
      conf = Redmine::Configuration['etherpad']
      unless conf and conf['host']
        raise "Please define etherpad parameters in configuration.yml."
      end

      unless obj
        return "{{etherpad()}}"
      end

      padname, *params = args
      options = build_options(conf, params)
      api_key = conf.fetch('apiKey', 'xxx')
      verify_ssl = conf.fetch('verifySSL', true)

      uri = URI.parse(conf['host'])
      http = Net::HTTP.new(uri.host, uri.port)
      unless uri.scheme.casecmp("https")
        http.use_ssl = true
      else
        http.use_ssl = false
      end
      unless verify_ssl
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end


      params = { 
        'apikey' => api_key,
        'name' => User.current.name,
        'authorMapper' => User.current.id
      }

      resdata = etherpad_request(http, uri, '/api/1/createAuthorIfNotExistsFor', params)
      author_id = resdata['data']['authorID']

      params = { 
        'apikey' => api_key, 
        'groupMapper' => obj.project.identifier
      }
      resdata = etherpad_request(http, uri, '/api/1/createGroupIfNotExistsFor', params)
      group_id = resdata['data']['groupID']

      params = { 
        'apikey' => api_key, 
        'groupID' => group_id,
        'padName' => padname 
      }
      resdata = etherpad_request(http, uri, '/api/1/createGroupPad', params)

      if resdata['code'] == 1
        group_pad = "#{group_id}$#{padname}"
      else
        group_pad = resdata['data']['padID']
      end

      # session still valid?
      update_session = false
      if not cookies[:sessionID].nil?
        params = { 
          'apikey' => api_key, 
          'sessionID' => cookies[:sessionID] 
        }
        resdata = etherpad_request(http, uri, '/api/1/getSessionInfo', params)
        if resdata['code'] == 1 or resdata['data']['validUntil'].to_i <= Time.now.to_i
          update_session = true
        else
          session_id = cookies[:sessionID]
        end
      end

      # update/create session
      if cookies[:sessionID].nil? or update_session
        expires = Time.now + 3600
        params = { 
          'apikey' => api_key, 
          'groupID' => group_id, 
          'authorID' => author_id, 
          'validUntil' => expires.to_i 
        }
        resdata = etherpad_request(http, uri, '/api/1/createSession', params)
        session_id = resdata['data']['sessionID']

        cookies[:sessionID] = { :value => session_id, :host => uri.host, :expires => expires }
        if http.use_ssl?
          cookies[:sessionID] =  { :value => session_id, :host => uri.host, :expires => expires, :secure => true }
        end
      end

      width = options.delete('width')
      height = options.delete('height')
      
      pad_url = "#{conf['host']}/auth_session?padName=#{URI.encode(group_pad)}&sessionID=#{session_id}"
      return CGI::unescapeHTML("<a href='#{pad_url}' target='blank'>Pad in eigenem Fenster öffnen</a><br><iframe src='#{pad_url}' width='#{width}' height='#{height}'></iframe>").html_safe
    end
  end
end
