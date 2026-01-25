# LibLog-1.0

LibLog-1.0 is a logging library for World of Warcraft. It allows other addons to use a standardized logging format which is configurable at runtime out of the
box.

## Quick example

![Log example](.github/images/example.png)

```lua
self:LogVerbose("A verbose message", 3.14, true)

self:LogDebug("A debug message", "with multiple", "strings")

self:LogInfo("An info message", { "with", 1, "inner", "table" })

self:LogWarning("A warning message", { with = { nested = { tables = 42 }}})

self:LogError(function()
	return "An error message", "using a callback function", false
end)

self:LogFatal(function()
	local result = {
		"A fatal message using a callback function that returns an array"
	}

	for i = 1, 10 do
		table.insert(result, i)
	end

	return result
end)
```

## Features

* Severity levels
* Information rich
* Color coding
* Table destructuring
* Callback functions
* Configurable
* Custom sinks

### Severity levels

LibLog-1.0 supports six severity levels. Messages are only logged if their level is equal to or higher than the configured threshold.

Level | Method | Prefix | When to use
----- | ------ | ------ | -----------
1 | LogFatal | FTL | A critical or otherwise unrecoverable error that halts execution.
2 | LogError | ERR | A high-severity logic failure, but execution can continue.
3 | LogWarning | WRN | User-error, or other non-breaking issues.
4 | LogInfo | INF | General status updates and runtime milestones.
5 | LogDebug | DBG | Code paths and state changes during active development.
6 | LogVerbose | VRB | High-frequency data or raw calculations.

By default, the minimum log level is set to `INF`.

### Information rich

LibLog-1.0 automatically adds some helpful information to the log message. Each log is prefexed with:

1. The severity level.
2. The name of the calling addon.

Additionally, messages with a DBG or VRB severity are also prefixed with the current timestamp, including milliseconds.

### Color coding

LibLog-1.0 formats messages using automatic color coding to make different severities visually distinctive, additionally, log contents are also automatically
color coded based on their value type.

### Table destructuring

LibLog-1.0 is able to automatically destructure tables (up to 5 levels deep). Tables are colorized to increase readability in the chat window.

### Callback functions

Some logs may require complex logic to be performed which is only used for a log message, if then that log is filtered out because of severity level, all that
computational power has gone to waste.

All log methods support a callback function which is executed on-demand, and can be used to create logs that need to perform heavy calculations. This ensures
that during normal gameplay performance is not affected by these logs.

### Configurable

LibLog-1.0 seamlessly integrates with AceConfig-3.0 which allows you to create a configuration option for the log level.

### Custom sinks

Custom sinks allow you to receive a callback when a message is logged, this allows you to create your own log stream.

## Getting started

To use this library, you need to embed it into your addon. This can be done automatically if you use AceAddon-3.0, or manually using LibStub.

```lua
-- Option 1, use AceAddon-3.0
MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibLog-1.0")

-- Option 2, manually use LibStub
MyAddon = {}
MyAddon.name = "MyAddon"
LibStub("LibLog-1.0"):Embed(MyAddon)
```

> ⚠️ **LibLog-1.0 works best when your addon contains a `name` property. If you use AceAddon-3.0, this happens automatically. When manually embedding using
LibStub, it's highly recommended to add a `name` property to your addon object.** ⚠️

### Usage

Once embedded, your addon gains access to several logging functions. They accept any number of arguments of any type. It's recommended to use multiple arguments
as that powers the color coding system.

```lua
MyAddon:LogInfo("Addon Loaded!", true, 42, { key = "value" })
-- Output: 1761.159 INF MyAddon: Addon Loaded! true 42 { key "value" }
```

#### Callbacks

Callback functions are accepted by any logging function, as long as it is the only argument provided.

```lua
MyAddon:LogVerbose(function()
  -- this code will only run if the log level is set to VERBOSE
  local result = {}

  for i = 1, GetNumGroupMembers() do
      table.insert(result, UnitName("party" .. i))
  end

  return result -- Can return a table or varargs
end)
```

#### AceConfig

You can integrate a log level setting directly into your AceConfig-3.0 options table.

```lua
{
	logLevel = MyAddon:GetLogLevelOptionObject(MyAddon.db.global)
}
```

This allows you to directly pass in your configuration table, which is usually your saved variables. LibLog-1.0 will automatically read from and write to the
specified configuration table.

You can further control the options object by using a mixin:

```lua
{
	logLevel = Mixin(MyAddon:GetLogLevelOptionObject(MyAddon.db.global), {
		order = 10
	})
}
```

#### Initialization

Since your log level is stored in your own saved variables, you must tell LibLog-1.0 to use the correct log level upon load:

```lua
function MyAddon:OnInitialize()
	MyAddon.db = LibStub("AceDB-3.0"):New("MyAddonDB")

    MyAddon:SetLogLevelFromConfigTable(MyAddon.db.global)
end
```

#### Syncing changes

If the log level is changed externally (for example, via a global manager), you can react using the `OnLogLevelChanged` callback. This callback may either
perform its own syching logic, or simply return your configuration table.

```lua
function MyAddon:OnLogLevelChanged(level)
	return MyAddon.db.global
end
```

#### Custom sinks

It's possible to register a custom log sink, allowing you to capture all log messages, and recreate the log stream.

```lua
--- @param addon? string The name of the addon that sent the log message
--- @param level LogLevel The log severity
--- @param prefix string The prefix generated by the logging system.
--- @param message string The fully constructed message, including destructured values and color codes.
local function MyLogSink(addon, level, prefix, message)
	print(prefix .. " " .. message)
end

LibLog:RegisterSink(MyLogSink)
```

## External integrations

The [LogManager](https://github.com/Snakybo/LogManager) addon is an example of an external log level manager. It's able to manage both the global minimum
logging level, as well as per-addon settings.
