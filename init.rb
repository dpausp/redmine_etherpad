#
# vendor/plugins/redmine_etherpad_auth/init.rb
#

require 'redmine'
require 'uri'
require 'net/http'
require 'json'
require 'time'
require 'date'

Redmine::Plugin.register :redmine_etherpad_auth do
  name 'Redmine Etherpad plugin with Group Authentication'
  author 'Martin Draexler'
  description 'Embed etherpad-lite pads in redmine wikis with authentication. Based on the redmine_etherpad plugin by Charlie DeTar'
  version '0.0.1'
  url 'https://upb.de'
  author_url 'https://upb.de'

  Redmine::WikiFormatting::Macros.register do
    desc "Embed etherpad with auth"
    macro :etherpadauth do |obj, args|
      conf = Redmine::Configuration['etherpadauth']
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


      uri = URI(conf['host'] + '/api/1/createAuthorIfNotExistsFor')
      params = { 'apikey' => controls['apiKey'], 'name' => controls['userName'], 'authorMapper' => controls['userId'] }
      res = Net::HTTP.post_form(uri, params)
      resdata = JSON.parse(res.body)
      controls['authorId'] = resdata['data']['authorID']

      uri = URI(conf['host'] + '/api/1/createGroupIfNotExistsFor')
      params = { 'apikey' => controls['apiKey'], 'groupMapper' => controls['projectId'] }
      res = Net::HTTP.post_form(uri, params)
      resdata = JSON.parse(res.body)
      controls['groupId'] = resdata['data']['groupID']

      uri = URI(conf['host'] + '/api/1/createGroupPad')
      params = { 'apikey' => controls['apiKey'], 'groupID' => controls['groupId'], 'padName' => padname }
      res = Net::HTTP.post_form(uri, params)
      resdata = JSON.parse(res.body)
      controls['groupPad'] = resdata['data']['padID']

      uri = URI(conf['host'] + '/api/1/createSession')
      params = { 'apikey' => controls['apiKey'], 'groupID' => controls['groupId'], 'authorID' => controls['authorId'], 'validUntil' => Time.now.to_i+(60*60) }
      res = Net::HTTP.post_form(uri, params)
      resdata = JSON.parse(res.body)
      controls['sessionId'] = resdata['data']['sessionID']

      cookies[:sessionID] = { :value => controls['sessionId'], :domain => ".fg-cn-pgsp1.cs.upb.de"}

      width = controls.delete('width')
      height = controls.delete('height')

      def hash_to_querystring(hash)
        hash.keys.inject('') do |query_string, key|
          query_string << '&' unless key == hash.keys.first
          query_string << "#{URI.encode(key.to_s)}=#{URI.encode(hash[key].to_s)}"
        end
      end
      
      return CGI::unescapeHTML("<iframe src='#{conf['host']}/p/#{URI.encode(controls['groupPad'])}?#{hash_to_querystring(controls)}' width='#{width}' height='#{height}'></iframe>")
    end
  end
end
