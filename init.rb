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

      # Defaults from configuration.
      controls = {
        'showControls' => conf.fetch('showControls', true),
        'showChat' => conf.fetch('showChat', true),
        'showLineNumbers' => conf.fetch('showLineNumbers', false),
        'useMonospaceFont' => conf.fetch('useMonospaceFont', false),
        'noColors' => conf.fetch('noColors', false),
        'width' => conf.fetch('width', '640px'),
        'height' => conf.fetch('height', '480px'),
        'apiKey' => conf.fetch('apiKey', 'xxx'),
        'verifySSL' => conf.fetch('verifySSL', true),
      }

      # Override defaults with given arguments.
      padname, *params = args
      for param in params
        key, val = param.strip().split("=")
        unless controls.has_key?(key)
          raise "#{key} not a recognized parameter."
        else
          controls[key] = val
        end
      end

      # Set current user name.
      if User.current
        controls['userName'] = User.current.name
        controls['userId'] = User.current.id
      elsif conf.fetch('loginRequired', true)
        return "TODO: embed read-only."
      end

      if obj
        controls['projectName'] = obj.project.name
        controls['projectId'] = obj.project.identifier
      else
        return "Invalid obj context"
      end

      uri = URI.parse(conf['host'])
      #binding.pry
      http = Net::HTTP.new(uri.host, uri.port)
      unless uri.scheme.casecmp("https")
        http.use_ssl = true
      else
        http.use_ssl = false
      end
      if not controls['verifySSL']
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      params = { 'apikey' => controls['apiKey'], 'name' => controls['userName'], 'authorMapper' => controls['userId'].to_s() }
      res = http.post((uri.path.nil? ? '' : uri.path) + '/api/1/createAuthorIfNotExistsFor', hash_to_querystring(params))
      resdata = JSON.parse(res.body)
      controls['authorId'] = resdata['data']['authorID']

      params = { 'apikey' => controls['apiKey'], 'groupMapper' => controls['projectId'].to_s() }
      res = http.post((uri.path.nil? ? '' : uri.path) + '/api/1/createGroupIfNotExistsFor', hash_to_querystring(params))
      resdata = JSON.parse(res.body)
      controls['groupId'] = resdata['data']['groupID']

      params = { 'apikey' => controls['apiKey'], 'groupID' => controls['groupId'].to_s(), 'padName' => padname }
      res = http.post((uri.path.nil? ? '' : uri.path) + '/api/1/createGroupPad', hash_to_querystring(params))
      resdata = JSON.parse(res.body)

      if resdata['code'] == 1
        controls['groupPad'] = "#{controls['groupId']}$#{padname}"
      else
        controls['groupPad'] = resdata['data']['padID']
      end

      # session still valid?
      update_session = false
      if not cookies[:sessionID].nil?
        params = { 'apikey' => controls['apiKey'], 'sessionID' => cookies[:sessionID] }
        res = http.post((uri.path.nil? ? '' : uri.path) + '/api/1/getSessionInfo', hash_to_querystring(params))
        resdata = JSON.parse(res.body)
        if resdata['code'] == 1 or resdata['data']['validUntil'].to_i <= Time.now.to_i
          update_session = true
        else
          session_id = cookies[:sessionID]
        end
      end

      # update/create session
      if cookies[:sessionID].nil? or update_session
        expires = Time.now + 3600
        params = { 'apikey' => controls['apiKey'], 'groupID' => controls['groupId'], 'authorID' => controls['authorId'], 'validUntil' => expires.to_i }
        res = http.post((uri.path.nil? ? '' : uri.path) + '/api/1/createSession', hash_to_querystring(params))
        resdata = JSON.parse(res.body)
        controls['sessionId'] = session_id = resdata['data']['sessionID']

        cookies[:sessionID] = { :value => controls['sessionId'], :host => uri.host, :expires => expires }
        if http.use_ssl?
          cookies[:sessionID] =  { :value => controls['sessionId'], :host => uri.host, :expires => expires, :secure => true }
        end
      end

      width = controls.delete('width')
      height = controls.delete('height')
      controls.delete('apikey')
      
      pad_url = "#{conf['host']}/auth_session?padName=#{URI.encode(controls['groupPad'])}&sessionID=#{session_id}"
      return CGI::unescapeHTML("<a href='#{pad_url}' target='blank'>Pad in eigenem Fenster öffnen</a><br><iframe src='#{pad_url}' width='#{width}' height='#{height}'></iframe>").html_safe
    end
  end
end
