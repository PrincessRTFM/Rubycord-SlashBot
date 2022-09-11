#!/usr/bin/env ruby

# PUBLIC GLOBALS
# These can be used in handlers in the appropriate locations

# @content["ty[e"]
$CTYPE_MESSAGE = 4 # normal message
$CTYPE_UPDATE = 7 # edit an existing message (from this app)
$CTYPE_MODAL = 9 # create a modal for the user

# @content["data"]["flags"]
$MFLAG_NOEMBED = 1 << 2 # message flag: suppress embeds
$MFLAG_EPHEMERAL = 1 << 6 # message flag: ephemeral
# END PUBLIC GLOBALS

require 'json'
require 'configurate'
require 'configurate/provider/toml'
require 'faraday'
require 'thor'

$Config = Configurate::Settings.create do
	add_provider Configurate::Provider::Env
	add_provider Configurate::Provider::TOML, 'config.toml', required: false
	add_provider Configurate::Provider::YAML, 'config.yml', required: false
	add_provider Configurate::Provider::YAML, 'config.yaml', required: false
	add_provider Configurate::Provider::YAML, 'config.json', required: false
	add_provider Configurate::Provider::StringHash, {
		"discord" => {
			"appid" => nil,
			"pubkey" => nil,
			"secret" => nil,
		},
		"http" => {
			"port" => 8080,
		},
	}
	add_provider Configurate::Provider::Dynamic
end

$ApiEndpoint = "/api/v10"

$EX_MISSING_CONFIG = 1
$EX_DISCORD_HTTP_ERROR = 2
$EX_INTERNAL_ERROR = 128
$EX_ENGINE_LOAD_ERROR = 256

def getAppId
	if $Config.discord.appid.nil? || $Config.discord.appid.empty? then
		STDERR.puts "Must provide application ID in environment variable DISCORD_APPID\n"
		STDERR.puts "or in `discord.appid` value of configuration file.\n"
		exit $EX_MISSING_CONFIG
	end
	return $Config.discord.appid.get
end
def getAppSecret
	if $Config.discord.secret.nil? || $Config.discord.appid.empty? then
		STDERR.puts "Must provide application oauth in environment variable DISCORD_SECRET\n"
		STDERR.puts "or in `discord.secret` value of configuration file.\n"
		exit $EX_MISSING_CONFIG
	end
	return $Config.discord.secret.get
end
def getPublicKey
	if $Config.discord.pubkey.nil? || $Config.discord.pubkey.empty? then
		STDERR.puts "Must provide application public key in environment variable DISCORD_PUBKEY\n"
		STDERR.puts "or in `discord.pubkey` value of configuration file.\n"
		exit $EX_MISSING_CONFIG
	end
	return $Config.discord.pubkey.get
end
def getBearerToken
	id = getAppId
	secret = getAppSecret
	payload = {
		grant_type: "client_credentials",
		scope: "identify connections",
	}
	http = Faraday.new("https://discord.com") do |conn|
		conn.request :authorization, :basic, id, secret
		conn.request :url_encoded
	end
	tokenRes = http.post "#{$ApiEndpoint}/oauth2/token", payload
	if tokenRes.status == 200 then
		return JSON.parse(tokenRes.body)["access_token"]
	end
	return nil
end
def getBearerClient
	token = getBearerToken
	return Faraday.new("https://discord.com") do |conn|
		conn.request :authorization, "Bearer", token
	end
end

class SlashBot < Thor
	class_option :verbose, :desc => "Log debugging information", :type => :boolean, :aliases => ["v"]

	desc "register COMMAND DESCRIPTION [OPTIONS...]", "register a simple slash command"
	long_desc <<-LONGDESC
Register a slash command with your discord application, optionally providing arguments for it.

Options to your command are single strings in the form "<type>[?][@<choices>|=<min>,<max>]#<name>:<description>". The type can be one of string, int/integer, float/number, bool/boolean, user, channel, role, or mentionable. If it is suffixed with `?` then it will be optional, otherwise it will be mandatory. Mandatory option descriptors MUST come before optional ones. For string, integer, and float types, you can provide a comma-delimited list of allowed values separated from the type with an `@`, OR you can provide a min and max separated from the type with an `=`, which will be min/max values for ints and floats and min/max length for strings.

If the type is a channel, then the choices will determine which channel types are shown, and may consist of text, voice, category, news/announcement, news-thread/announcement-thread, public-thread, and private-thread.

Example: `string#message:The message to echo back to you` will present a single string option named "Message" with the description "The message to echo back to you", allowing the user to type anything they want.

Example: `int@4,6,8,10,12,20#sides:The number of sides on the die to roll` will present a single integer option named "Sides" with the description "The number of sides on the die to roll", allowing ONLY the values 4, 6, 8, 10, 12, or 20.

Example: `int?=1,1000#count:The number of dice to roll` will allow specifying any number of dice from 1 (inclusive) to 1000 (inclusive) to roll, as an optional parameter.
	LONGDESC
	option :guild, :desc => "Register the command for the specified discord server, instead of globally", :aliases => ["g"]
	option :direct, :desc => "Allow the command to be used in DMs if you have an application bot (global only)", :aliases => ["d"], :type => :boolean
	option :admin, :desc => "Restrict the command to admins by default", :type => :boolean
	option :perms, :desc => "Require the user have the given permissions, as a decimal-serialised bitstring (ADVANCED)"
	def register(name, desc, *optStrs)
		id = getAppId
		guild = options[:guild] ? "/guilds/#{options[:guild]}" : ""
		path = "#{$ApiEndpoint}/applications/#{id}#{guild}/commands"
		http = getBearerClient
		command = {
			name: name,
			type: 1,
			description: desc,
			options: [],
			dm_permission: false,
		}
		if guild.empty? then
			if options[:direct] then
				command["dm_permission"] = true
			end
			if options[:admin] then
				command["default_member_permissions"] = "0"
			elsif options[:perms] then
				command["default_member_permissions"] = options[:perms]
			end
		end
		optStrs.each do |optstr|
			optstr.match %r{
				^
				\s*
				(?<type>
					string
					|
					int(?:eger)?
					|
					float
					|
					number
					|
					bool(?:ean)?
					|
					user
					|
					channel
					|
					role
					|
					mention(?:able)?
				)
				\s*
				(?<optional>
					\??
				)
				\s*
				(?<details>
					(?:
						@ \s* [^#]+
						|
						= \s* (?:\d*\.?\d+|inf) \s* , \s* (?:\d*\.?\d+|inf)
					)?
				)
				\s*
				\#
				\s*
				(?<name>
					[^:]+?
				)
				\s*
				:
				\s*
				(?<description>
					.+?
				)
				\s*
				$
			}uix do |m|
				type = m["type"]
				case type
				when "string"
					type = 3
				when "int", "integer"
					type = 4
				when "bool", "boolean"
					type = 5
				when "user"
					type = 6
				when "channel"
					type = 7
				when "role"
					type = 8
				when "mention", "mentionable"
					type = 9
				when "float", "number"
					type = 10
				else
					raise "UNPOSSIBLE"
				end
				choices = nil
				min = nil
				max = nil
				details = m["details"]
				if !details.empty? then
					if details.start_with? "@" then
						choices = details.delete_prefix("@").split(",").map do |s|
							v = s.strip
							case type
							when 7
								case v
								when "text"
									v = 0
								when "voice"
									v = 2
								when "category"
									v = 4
								when "news", "announcement"
									v = 5
								when "news-thread", "announcement-thread"
									v = 10
								when "public-thread"
									v = 11
								when "private-thread"
									v = 12
								else
									raise "UNPOSSIBLE"
								end
							when 4
								v = v.to_i
							when 10
								v = v.to_f
							end
						end
					elsif details.start_with? "=" then
						parts = details.delete_prefix("=").split(",").map do |s|
							s.strip.downcase
						end
						if type == 4 then
							min = parts[0].to_i unless min == "inf"
							max = parts[1].to_i unless max == "inf"
						elsif type == 10 then
							min = parts[0].to_f unless min == "inf"
							max = parts[1].to_f unless max == "inf"
						end
					end
				end
				opt = {
					type: type,
					name: m["name"].strip.downcase,
					description: m["description"].strip,
					required: m["optional"].empty?,
				}
				if !choices.nil? then
					case type
					when 3, 4, 10
						opt["choices"] = choices.map do |v|
							{
								name: v,
								value: v,
							}
						end
					when 7
						opt["channel_types"] = choices
					end
				end
				if type == 4 || type == 10 then
					opt["min_value"] = min unless min.nil?
					opt["max_value"] = max unless max.nil?
				elsif type == 3 then
					opt["min_length"] = min unless min.nil?
					opt["max_length"] = max unless max.nil?
				end
				command[:options].push(opt)
			end
		end
		payload = JSON.generate command
		puts payload if options[:verbose]
		addRes = http.post path, payload, "Content-Type" => "application/json"
		STDERR.puts "#{addRes.body}\n" if options[:verbose]
		if addRes.status == 201 then
			response = JSON.parse addRes.body
			puts "Command registered: #{response["name"]} (\##{response["id"]})\n"
		else
			STDERR.puts "Failed to create/update command: HTTP #{addRes.status}\n"
			exit $EX_DISCORD_HTTP_ERROR
		end
	end

	desc "delete IDS...", "delete a command by its ID"
	option :guild, :desc => "Remove the command from the specified discord server, instead of the global set", :aliases => ["g"]
	def delete(*cmds)
		id = getAppId
		guild = options[:guild] ? "/guilds/#{options[:guild]}" : ""
		path = "#{$ApiEndpoint}/applications/#{id}#{guild}/commands"
		http = getBearerClient
		failed = false
		cmds.each do |cmd|
			delRes = http.delete "#{path}/#{cmd}"
			STDERR.puts "#{delRes.body}\n" if options[:verbose]
			if delRes.status == 204 then
				puts "Command deleted (\##{cmd})\n"
			else
				STDERR.puts "Failed to delete command \##{cmd}: HTTP #{delRes.status}\n"
				failed = true
			end
		end
		exit $EX_DISCORD_HTTP_ERROR if failed
	end

	desc "query", "query registered commands"
	option :guild, :desc => "Query commands on the specified discord server, instead of global ones", :aliases => ["g"]
	def query
		guild = options[:guild] ? "/guilds/#{options[:guild]}" : ""
		path = "#{$ApiEndpoint}/applications/#{getAppId}#{guild}/commands"
		http = getBearerClient
		puts "Querying #{guild.empty? ? 'global' : 'guild'} commands...\n"
		queryRes = http.get path
		STDERR.puts "#{queryRes.body}\n" if options[:verbose]
		if queryRes.status != 200 then
			STDERR.puts "Failed to query command list: HTTP #{queryRes.status}\n"
			exit $EX_DISCORD_HTTP_ERROR
		end
		commands = JSON.parse queryRes.body # [ {...}, {...}, ... ]
		puts "#{commands.length} command#{commands.length == 1 ? '' : 's'} registered\n"
		commands.each do |cmd|
			type = cmd["type"] || 1
			next unless type == 1
			id = cmd["id"]
			name = cmd["name"]
			desc = cmd["description"]
			opts = cmd["options"] || []
			dms = cmd["dm_permission"]
			dms = true if dms.nil?
			puts "> #{name}: #{desc} (\##{id})\n"
			puts "  > DM usage #{dms ? 'on' : 'off'}, #{opts.length} option#{opts.length == 1 ? '' : 's'}\n"
		end
	end

	desc "launch", "launch the bot"
	def launch
		require 'ed25519'
		require 'sinatra'
		disable :static, :logging, :method_override, :run
		verifyKey = begin
			Ed25519::VerifyKey.new [$Config.discord.pubkey.get.to_s].pack 'H*'
		rescue ArgumentError => e
			STDERR.puts "#{e.message}\n"
			exit $EX_INTERNAL_ERROR
		end
		set :port, $Config.http.port.get
		before do
			puts "PATH=#{request.path}, FILE=#{request.script_name}, INFO=#{request.path_info}\n" if options[:verbose]
			sig = request.env["HTTP_X_SIGNATURE_ED25519"]
			time = request.env["HTTP_X_SIGNATURE_TIMESTAMP"]
			if sig.nil? || time.nil? then
				# Not a discord request
				puts "Not a discord webhook request - ignoring\n" if options[:verbose]
				halt 501, 'unknown request'
			end
			request.body.rewind
			content = request.body.read
			request.body.rewind
			begin
				verifyKey.verify [sig].pack('H*'), time + content
			rescue Ed25519::VerifyError
				body 'invalid request signature'
				halt 401 # Discord REQUIRES that failed validation be given a 401 status
			end
			if content.start_with? '{' then # try it as JSON
				begin
					@data = JSON.parse content
					if @data["type"].nil? then
						puts "Received invalid request (no `type` property)\n" if options[:verbose]
						body 'unknown request type'
						halt 422 # unprocessable entity
					else
						case @data["type"]
						when 1 # PING
							puts "Received ping event\n" if options[:verbose]
							@content = {type: 1}
							halt 200
						when 2 # command used!
							puts "Received command event\n" if options[:verbose]
							request.path_info = "/" + @data['data']['name']
							@content = nil
							pass
						when 3 # component interaction - things like buttons, for instance
							puts "Received component-interaction event\n" if options[:verbose]
							request.path_info = "/component/" + @data['data']['custom_id']
							@content = nil
							pass
						else
							puts "Received unknown request (type #{@data["type"]})\n" if options[:verbose]
							body 'unknown request type'
							halt 422 # unprocessable entity
						end
					end
				rescue JSON::ParserError
					body 'invalid json'
					halt 400 # bad request
				end
			else
				puts "Invalid request body - ignoring\n" if options[:verbose]
				body 'unknown content type'
				halt 415 # unsupported media type
			end
		end
		after do
			if response.status == 200 then
				if @content.nil? then
					if body.empty? then
						puts "Request succeeded with empty body\n" if options[:verbose]
						headers "Content-Type" => "text/plain"
						body 'this space intentionally left blank'
					else
						STDERR.puts "Request handler wrote response body directly - consider using @content instead\n" if options[:verbose]
						body body.join + "\n" unless body.last.end_with? "\n"
					end
				else
					puts "Request succeeded, serialising response content\n" if options[:verbose]
					headers "Content-Type" => "application/json"
					body JSON.generate @content
				end
			elsif response.status >= 400 && response.status < 500 then
				puts "Request failed (client error)\n" if options[:verbose] && response.status != 401
				headers "Content-Type" => "text/plain"
			end
		end
		puts "Initialising SlashBot\n" if options[:verbose]
		begin
			Dir.mkdir "handlers"
		rescue Errno::EEXIST
			# nop
		rescue SystemCallError => e
			STDERR.puts "Failed to create `handlers/` directory: #{e.message}\n"
			exit $EX_INTERNAL_ERROR
		end
		begin
			puts "Loading handlers\n" if options[:verbose]
			Dir.glob "handlers/*.rb" do |file|
				puts "Loading handler file #{File.basename file}\n"
				load file
			end
		rescue LoadError => e
			STDERR.puts "Error loading handler: #{e.message}\n"
			exit $EX_ENGINE_LOAD_ERROR
		rescue => e
			STDERR.puts "Failed to load handlers: #{e.message}\n"
			exit $EX_INTERNAL_ERROR
		end
	end
end

SlashBot.start(ARGV)
