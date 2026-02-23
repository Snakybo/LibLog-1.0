# LibLog-1.0

LibLog-1.0 is a logging library for World of Warcraft. It aims to be easy to use with a simple API. LibLog-1.0's biggest feature is that its built for
structured logging.

There are several related addons available which can capture the output of LibLog-1.0 and visualize it to an [in-game window](https://github.com/Snakybo/LogSink-Table), or [saved variables](https://github.com/Snakybo/LogSink-SavedVariables).

```lua
MyAddon:LogInfo("My current health is {health}, and I have {mana} mana", UnitHealth("player"), UnitPower("player"))
```

LibLog-1.0 uses a lite¹ version of [Message Templates](https://messagetemplates.org/), which is a DSL that standardizes formatted strings with named
parameters. Instead of formatting variables directly into the text, LibLog-1.0 captures the value associated with the value.

The above example will record two properties (`health`, and `mana`) in the log object, when inspecting the log object, they appear in a `properties` table,
alongside the timestamp, message, and log level.

```lua
{
  -- <other fields omitted>
  properties = {
    health = 50,
    mana = 100
  }
}
```

Note that even though LibLog-1.0 is built to work with structured logs, it will first and foremost still print human-readable text into the chat window.
When no additional sink addons are installed, that's all it does. It still offers the full suite of features, they will just be mostly transparant, which is how
99.9% of users will experience it.

¹ Lite because it doesn't support the more advanced features such as `@`, `$`, and `:000`.

## Structured logging.. but why?

Traditional (unstructured) logging simply writes plain text messages that can contain variable data.

```lua
print("My name is", UnitName("player"), "on realm", UnitRealm("player"))
-- My name is Arthas on realm Frostmourne
```

Whilst this is perfectly readable, its difficult to parse and extract data from. For example, if you prefix your logs with the name of the player that performed
the action, it'd be difficult to reliably filter those logs to a specific player.

```txt
Thrall: UNIT_SPELLCAST_SUCCEEDED Bloodlust
Khadgar: UNIT_SPELLCAST_SUCCEEDED Blink
Thrall: UNIT_SPELLCAST_FAILED Lightning Bolt
Khadgar: UNIT_SPELLCAST_SUCCEEDED Fire Blast
```

Try determining who cast Bloodlust, who failed a cast, which player cast the most abilities, etc. especially if the number of players increases to 20, and the
amount of logs increases to the duration of a typical raid fight.

Structured logging solves this by capturing and organizing data into consistent fields. With structured logging, each of the previous logs will contain the same
properties.

```lua
{
  -- <other fields omitted>
  properties = {
    name = "Thrall",
    eventName = "UNIT_SPELLCAST_SUCCEEDED",
	spellName = "Bloodlust"
  }
},
{
  -- <other fields omitted>
  properties = {
    name = "Khadgar",
    eventName = "UNIT_SPELLCAST_SUCCEEDED",
	spellName = "Blink"
  }
}
```

This makes it trivial to query on this data and answer the above questions. It also opens the way for more debuggable addons by visualizing this data.

## Features

* Simple logging API with well-known levels such as `DEBUG`, `INFO`, `WARNING`, `ERROR`, and `FATAL`
* Configurable minimum logging levels, either globally, or per-addon
* Support for custom sinks, to capture and process logs in real-time
* And more...

## Getting started

Like many other libraries, LibLog-1.0 must be embedded within your addon. When using AceAddon-3.0, this can be done automatically, otherwise, you can do so
using LibStub.

```lua
-- Option 1, use AceAddon-3.0
MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibLog-1.0")

-- Option 2, manually use LibStub
-- NOTE: LibLog-1.0 works best when your addon contains a 'name' property. If you use AceAddon-3.0, this is set automatically.
-- When manually embedding using LibStub, it's highly recommended to add a 'name' property to your addon object
MyAddon = {}
MyAddon.name = "MyAddon"
LibStub("LibLog-1.0"):Embed(MyAddon)

MyAddon:LogInfo("Hello {name}!", MyAddon.name)
-- Hello MyAddon!
```

### Log levels

LibLog-1.0 implements six severity levels, combined with a minimum level to process log objects.

Level | Method | When to use
----- | ------ | -----------
6 | LogFatal | A critical or otherwise unrecoverable error that must halt execution.
5 | LogError | A high-severity logic issue that leaves functionality unavailable or expections broken.
4 | LogWarning | User-error, or other non-breaking issues.
3 | LogInfo | General status updates and runtime milestones.
2 | LogDebug | Code paths and state changes that are useful when determining how something happened.
1 | LogVerbose | High-frequency, noisy data that is rarely enabled outside of debugging.

By default, the minimum log level is set to `Info`, meaning `Info` and higher levels are processed.

### Configuration

You can override the minimum log level for your addon by using the following functions:

```lua
MyAddon:SetLogLvel(LibLog.LogLevel.VERBOSE)
MyAddon:GetLogLevel()
```

It's likely also desirable to initialize the logger upon startup, as your configured minimum log level is not persisted by the library — that responsibility is
for your addon itself. LibLog-1.0 does offer functionality to _mostly_ do it for you.

```lua
function MyAddon:OnInitialize()
	MyAddon.db = LibStub("AceDB-3.0"):New("MyAddonDB")

	-- Simply pass in your saved variables table
    MyAddon:SetLogLevelFromConfigTable(MyAddon.db.global)
end
```

If using AceConfig-3.0, you can integrate a dropdown to set the log level for your addon directly:

```lua
{
	logLevel = MyAddon:GetLogLevelOptionObject(MyAddon.db.global)
}
```

```lua
{
	logLevel = Mixin(MyAddon:GetLogLevelOptionObject(MyAddon.db.global), {
		order = 10
	})
}
```

If not using AceConfig-3.0, all required properties to build a dropdown youself are publicly available: `LibLog.LogLevel`, `LibLog.CONFIG_KEY`, and of course
`MyAddon:SetLogLevel` and `MyAddon:GetLogLevel`.

## Advanced configuration

### Callback functions

Sometimes a log may require complex logic to be performed which is only used for that log, if then that log is filtered out because of severity level, all that
computational power has gone to waste.

All log methods support a callback function which is executed on-demand, and can be used to create logs that need to perform heavy calculations. This ensures
that during normal gameplay performance is not affected by these logs.

```lua
MyAddon:LogVerbose("Currently in a raid with {members}", function()
  -- this code will only run if the log level is set to VERBOSE
  local result = {}

  for i = 1, GetNumGroupMembers() do
      table.insert(result, UnitName("raid" .. i))
  end

  return result
end)
```

Alternatively, you can use `IsLogLevelEnabled` to check whether logging should occur.

```lua
if MyAddon:IsLogLevelEnabled(LibLog.LogLevel.DEBUG) then
  local members = {}

  for i = 1, GetNumGroupMembers() do
      table.insert(members, UnitName("raid" .. i))
  end

  MyAddon:LogDebug("Currently in a raid with {members}", members)
end
```

### Halting execution

The fatal log level is a bit special, it behaves just like a regular log would, however it will also show up in BugSack as a captured error. This ensures that
execution is halted, just like a regular `error(...)` would.

All log functions return an `unknown` value, for the sole purpose of being able to immediately return after the log. Since LuaLS or the likes doesn't know that
`LogFatal` does not return, it may be desirable to `return MyAddon:LogFatal(...)`.

### Additional properties

You can also add extra properties to a log object, these are only included in the `properties` table, and not visible within the message itself. It's also
possible to push a callback function as property, these will be evaluated on-demand with every log, allowing you to capture up-to-date information.

```lua
MyAddon:PushLogProperty("extra", 41)
MyAddon:PushLogProperty("anotherProperty", function()
	return UnitHealth("player")
end)
```

After pushing a property, all logs your addon produces will contain the value of that property, until popped.

```lua
MyAddon:PopLogProperty("extra", "anotherProperty")
```

You can also use closures to automatically manage pushing and popping properties:

```lua
MyAddon:WithLogContext({ extra = 41, anotherProperty = function() return UnitHealth("player") end }, function()
	MyAddon:LogInfo("This log will have additional properties")

	-- <logic>

	MyAddon:LogVerbose("This log will still have additional properties")
end)
```

## Formatting

LibLog-1.0 (currently) implements a an opinionated color scheme for log levels and value types, and a format for destructured tables.

The format of destructured tables is also intended to make use of color as a seperator and thus leave out excess data. At its most basic level, a destructured
table will look like this:

```txt
{ key value }

{ 1 value 2 value 3 value 4 value }

{ key { key2 { key3 value } } }
```

## Custom sinks

And finally, the primary reason LibLog-1.0 exists, custom sinks to process log objects.

To register a custom sink, use the following function:

```lua
--- @param message LibLog-1.0.LogMessage
local function OnLogReceived(message)
	print(message.message)
end

LibLog:RegisterSink("MyLogSink", OnLogReceived)
```

The `LibLog-1.0.LogMessage` message object contains all relevant information for the log message, including the value of each individial property.

```lua
{
  message = "My character name is Arthas on realm Frostmourne",
  addon = "MyAddon",
  level = 4,
  time = 1771420921,
  sequenceId = 1,
  properties = {
    charName = "Arthas",
    realmName = "Frostmourne"
  }
}
```

You can also enable or disable registered sinks:

```lua
LibLog:EnableSink("MyLogSink")
LibLog:DisableSink("MyLogSink")
```

### Available sinks

* [LogSink: Table](https://github.com/Snakybo/LogSink-Table)
* [LogSink: SavedVariables](https://github.com/Snakybo/LogSink-SavedVariables)
