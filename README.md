# SlashBot

[![GitHub last commit](https://img.shields.io/github/last-commit/PrincessRTFM/Rubycord-SlashBot?logo=github)](https://github.com/PrincessRTFM/Rubycord-SlashBot/commits/master)
[![GitHub issues](https://img.shields.io/github/issues-raw/PrincessRTFM/Rubycord-SlashBot?logo=github)](https://github.com/PrincessRTFM/Rubycord-SlashBot/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc)
[![GitHub closed issues](https://img.shields.io/github/issues-closed-raw/PrincessRTFM/Rubycord-SlashBot?logo=github)](https://github.com/PrincessRTFM/Rubycord-SlashBot/issues?q=is%3Aissue+is%3Aclosed+sort%3Aupdated-desc)

A simple framework for HTTP-webhook slash commands on discord.

## Creating the application

If you don't have a discord application set up yet, you'll need to do that. This is done by going to the [developer portal](https://discord.com/developers/applications) and clicking the "New Application" button in the upper right corner.

Once you have your application, look at the General Information tab for it and find the application ID. It'll be a string of numbers, with a "copy" button under it. You'll need it to configure the bot if you want to use the utility features to manage your command registration, as well as to add your application to a discord server.

In the same place, you'll find your public key, just under your application ID. Hold onto that too, because you'll need _that_ to actually _run_ the framework. You can't receive commands without it, for security reasons.

Finally, open up the "OAuth2" panel (from the left sidebar) in a new tab. You'll need to generate a new secret and hold onto it - **it will be shown to you once** so be sure to save it somewhere secure! This is called your secret, oauth secret, or app secret. It's also required for use of the utility features to manage command registration.

## Adding the app to a server

You'll need to open the following link in your browser, while logged in to your discord account:

```
https://discord.com/oauth2/authorize?scope=applications.commands&client_id=YOUR_APP_ID
```

Discord will ask you to select a server to add the app to, and then confirm that you want to do it.

## Configuring the framework

The framework supports loading configration settings from environment variables, `config.toml`, `config.yml`, `config.yaml`, and `config.json` (checked in that order). If you use an environment variable, you need to set `DISCORD_PUBKEY` to your public key. In a config file, you need to set `discord.pubkey` however the language you choose does so. For example, in JSON:

```json
{
	"discord": {
		"pubkey": "YOUR_PUBLIC_KEY"
	}
}
```

In TOML:

```toml
[discord]
pubkey = "YOUR_PUBLIC_KEY"
```

YAML:

```yaml
discord:
  pubkey: YOUR_PUBLIC_KEY
```

You can also set `http.port` (or `HTTP_PORT` if you're using environment variables) to choose what port the framework will listen on. The default is `8080`.

Please note that if you want to use the utility commands listed below to manage command registration with discord, you will _also_ need to set `discord.appid`/`DISCORD_APPID` and `discord.secret`/`DISCORD_SECRET` to your application ID and your oauth2 secret.

Also note that you will see warnings about configuration files not existing (unless you, for some incomprehensible reason, create all four possible config files) every time you run the framework, no matter how you invoke it. These warnings can be safely ignored, as no config files are actually _required_. You could, if you so desire, use environment variables for all configuration. Even if you use config files (recommended, by the way) you only need one, in whatever format you personally prefer.

## Adding commands

If your command is already registered in your application, then all you need to do is add a handler for it. Under the `handlers/` directory, create a `.rb` file. The name can be anything, but it's recommended to use the name of your command. Within that file, add any setup at the top (for instance, adding default settings with `$Config.cmd.YOUR_COMMAND_NAME.SETTING_NAME = "default value"`), then create the actual handler as shown here:

```ruby
post "/MY_COMMAND_NAME" do
	# do things...
	@content = {
		# JSON object to return to discord's API
	}
end
```

With discord's "components" feature, you can add interactive components to returned messages. When the user interacts with them, SlashBot will receive the event and it will be dispatched in a very similar way. To understand how exactly to receive such events, you need to know that **message components are assigned unique custom IDs** when they're used in responses, which may be arbitrary text up to 100 characters. Interacting with these components sends that custom ID in the event. SlashBot will assign them to `/component/{CUSTOM_ID}`, which means that you can set an ID like `myButton/{json-encoded state information}` and a handler assigned to `post "/component/myButton/*" do |jsonState|` to receive events for that specific button _and_ still access the saved state. You can find more information about in-path parameters that can be used for more advanced tricks by looking under the "routes" section of [sinatra's documentation](https://sinatrarb.com/intro.html).

Important note: while you _can_ use sinatra's `body` call to set the output body directly (and use `headers` to set the content type), **this is not recommended**. The framework is designed to allow creating a JSON object (well, the Ruby equivalent, anyway) that will be automatically serialised with the appropriate headers. Further, be advised that if you set `@content` to any non-nil value, SlashBot will attempt to serialise it and use it as the response body.

Each `.rb` file under the `handlers/` directory will be loaded at startup, although load order is NOT guaranteed. If you need to load libraries, please use `require` and do _not_ put them under `handlers/`, as they may be loaded twice.

Please note that you still need to register your commands with discord before they will show up for people to user. Creating the handler file will only tell SlashBot how to respond to that command being used.

### SlashBot utility commands

SlashBot can register, list, and delete commands for you, as well as run the actual webhook response server.

#### Listing commands

```
$ ./slashbot.rb query [-g GUILD_ID | --guild GUILD_ID]
```

Without passing a guild ID, this will list all registered _global_ commands. The listing will include the command name and description, whether it's enabled in DMs for bot applications, and how many options it has. Naturally, if you pass a guild ID, only commands registered for that guild will be listed.

#### Deleting commands

```
$ ./slashbot.rb delete [-g GUILD_ID | --guild GUILD_ID] <IDs...>
```

This uses discord's "snowflake" IDs, not command names, in order to delete registered commands. As with listing, commands are deleted from the global set unless you pass a guild ID. You can pass as many command IDs as you want here, but you can't delete from more than one command set at a time.

#### Registering commands

If your command is _not_ yet registered in your application, you will need to do so before discord will recognise it and allow users to actually invoke it. Ordinarily, this is a complicated and annoying process to do manually, because discord doesn't offer a graphical interface, or even a premade commandline utility. Thankfully, SlashBot can actually handle this for you! Unfortunately, it's still a bit of a mess. Some examples will be provided.

```
$ ./slashbot.rb register [-g GUILD_ID | --guild GUILD_ID] <name> <description> [<option specifications...>]
```

If you only want a simple command (one with no options) then this is as simple as the `delete` function. Keep in mind that the command `name` will _always_ be forced into lowercase, as a restriction imposed by discord's API itself. The `description` will be unaffected. Also note that, at the time of this writing, names may not be longer than 32 characters and descriptions may not be longer than 100 characters. **This also applies to options.**

Now, the messy bit: option specifications. You're allowed up to 25 of these, and each one consists at a _minimum_ of three components (name, description, and type). As a result... the option specification format that SlashBot understands is a little complicated. The general layout is as such: `<type>[?][@<choices>|=<min>,<max>]#<name>:<description>`.

That's awful to look at, I know. I'm sorry. Here's a breakdown:

The `type` indicates what kind of input the command user can provide. The available options are:
- `string`
- `int` or `integer`
- `float` or `number`
- `bool` or `boolean`
- `user`
- `channel`
- `role`
- `mentionable` (includes both users and roles)

The type _may_ be followed by a `?` to indicate that this option isn't required. Please note that so-called "optional options" _cannot_ be followed by mandatory options, as a restriction imposed by discord's API.

Following the type (and following the `?` if provided) you can include _either_ a comma-delimited list (maximum 25 items, prefixed by `@`) or a comma-separated minimum and maximum (prefixed by `=`), which be interpreted depending on the `type` of this option, as listed below.

After the list or min/max values, if any, a `#` is used to indicate the option name. This must be lowercase and not more than 32 characters, as a restriction imposed by discord's API.

Following the option name is a `:` and then the option description, which must not exceed 100 characters, as a restriction imposed by discord's API.

<!-- I bet you're almost as sick of reading "as a restriction imposed by discord's API" as I am of writing it by now. -->

##### Lists, minimum, and maximum

For `string`, `int`/`integer`, and `float`/`number` options:

- A list will be treated as the only allowed values for this option. They will be presented to the user, who must select one. No other values may be used.

- A min/max wil be the minimum and maximum _value_ for numeric (integer and float) options, and the minimum and maximum _length_ for strings.

> Note that you _may_ use `inf` to disregard a specific limit, such as `=1,inf` to require a number that is _at least_ 1 but has no maximum. Technically, you could use `=inf,inf` to indicate no limits at all.

For `channel` options:

- Minimum and maximum are meaningless and will be ignored.

- A list will restrict the _types_ of channels that can be used, and may consist of the following values:

	- `text`
	- `voice`
	- `category`
	- `news` or `announcement`
	- `news-thread` or `announcement-thread`
	- `public-thread`
	- `private-thread`

##### Examples

```
$ register \
	"roll" \
	"Roll some dice" \
	"int@4,6,8,10,12,20,100#sides:How many sides per die?" \
	"int?=1,1000#count:How many dice to roll? (default 1)"
```

While implementation of this slash command is left as an exercise to the reader, this would register a command `/roll`, taking one required option as an integer that can only be given the values `4`, `6`, `8`, `10`, `12`, `20`, or `100`, described as the number os sides per die being rolled, and one optional option as an integer within the range `[1, 1000]` (bi-inclusive) described as the number of dice to roll. Please note that optional options that aren't provided when the command is used aren't sent; default values are the responsibility of the command handler itself. A default is indicated in the command option, but this is neither required nor actually used.

```
$ register \
	"echo" \
	"Take whatever message you write and echo it right back" \
	"string#message:The message to echo back to you"
```

Again leaving implementation to the reader, this would register `/echo`, taking one (required!) string option called `message`, described as the message to echo back to you, with no limits on length.

## Running the command app

Just launch the app with the command `launch`, as in `./slashbot.rb launch`. You will need your app's public key available, either in a config file or an environment variable, as described above in the configuration section.
