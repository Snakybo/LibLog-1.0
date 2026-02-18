-- MIT License
--
-- Copyright (c) 2026 Kevin Krol
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

if LibStub == nil then
	error("LibLog-1.0 requires LibStub")
end

--- @class LibLog-1.0.LogMessage
--- @field public message string The human-readable log string.
--- @field public level LibLog-1.0.LogLevel The (numeric) level of the log. Can be compared against `LibLog.LogLevel`, or stringified using `LibLog.labels`.
--- @field public addon? string The name of the source addon.
--- @field public time integer The number of seconds that have elapsed since the Unix epoch.
--- @field public sequenceId integer The unique sequence identifier of the log within the current second.
--- @field public properties table<string, unknown> All properties that have been extracted from the template string or manually injected.

--- @class LibLog-1.0.Sink
--- @field public callback fun(message: LibLog-1.0.LogMessage)
--- @field public enabled boolean

--- @class LibLog-1.0.MessageTemplate
--- @field public message string The parsed template string, where the named parameters have been replaced to conform with `string.format`.
--- @field public properties string[] The named parameters found within the template string.

--- @class LibLog-1.0.Property
--- @field public name string The name of the parameter.
--- @field public value unknown The raw value.
--- @field public isCallback boolean Whether the `value` is a `function`.

--- @class LibLog-1.0
local LibLog = LibStub:NewLibrary("LibLog-1.0", 7)
if LibLog == nil then
	return
end

--- @class LibLog-1.0.Logger
--- @field public name? string The name of the addon logs will be attributed to.
local Logger = {}

--- @enum LibLog-1.0.LogLevel
LibLog.LogLevel = {
	NONE = 0,
	VERBOSE = 1, -- High-frequency, noisy data that is rarely enabled outside of debugging.
	DEBUG = 2, -- Code paths and state changes that are useful when determining how something happened.
	INFO = 3, -- General status updates and runtime milestones.
	WARNING = 4, -- User-error, or other non-breaking issues.
	ERROR = 5, -- A high-severity logic issue that leaves functionality unavailable or expections broken.
	FATAL = 6 -- A critical or otherwise unrecoverable error that must halt execution.
}

LibLog.labels = {
	[LibLog.LogLevel.VERBOSE] = "VRB",
	[LibLog.LogLevel.DEBUG] = "DBG",
	[LibLog.LogLevel.INFO] = "INF",
	[LibLog.LogLevel.WARNING] = "WRN",
	[LibLog.LogLevel.ERROR] = "ERR",
	[LibLog.LogLevel.FATAL] = "FTL"
}

LibLog.colorScheme = {
	[LibLog.LogLevel.VERBOSE] = "ff6e6e6e",
	[LibLog.LogLevel.DEBUG] = "ffa1a1a1",
	[LibLog.LogLevel.INFO] = "ff00dfff",
	[LibLog.LogLevel.WARNING] = "ffffcf40",
	[LibLog.LogLevel.ERROR] = "ffff5f5f",
	[LibLog.LogLevel.FATAL] = "ffff0000",
	["table"] = "ff808080",
	["tableKey"] = "ffffa64d",
	["string"] = "fffff9b0",
	["number"] = "ff38ff70",
	["boolean"] = "ff99ff00",
	["nil"] = "ffff77ff",
	["event"] = "ffbd93f9",
}

LibLog.configKey = "logLevel"

--- @private
--- @type table<table, boolean>
LibLog.embeds = LibLog.embeds or {}

--- @private
--- @type table<string, LibLog-1.0.LogLevel>
LibLog.levels = LibLog.levels or {}

--- @private
--- @type table<string, LibLog-1.0.Sink>
LibLog.sinks = LibLog.sinks or {}

--- @private
--- @type table<string, table<string, LibLog-1.0.Property>>
LibLog.properties = LibLog.properties or {}

local L = {
	level = "Log level",
	level_desc = "Select the logging level for this addon. Select 'NONE' to completely disable logging.\n\nLower values mean more messages get logged, where 'VERBOSE' logs everything."
}

--- @type LibLog-1.0.LogLevel
local minLogLevel = LibLog.LogLevel.INFO

--- @type table<string, LibLog-1.0.MessageTemplate>
local templateCache = {}

--- @type table<table, boolean>
local tableCache = {}

local currentTime = 0
local currentSequenceId = 1

--- @param err any
--- @return function
local function ErrorHandler(err)
	return geterrorhandler()(err)
end

local function AcquireCachedTable()
	local result = next(tableCache)

	if result ~= nil then
		tableCache[result] = nil
		return result
	end

	return {}
end

--- @param tbl table
local function ReleaseCachedTable(tbl)
	for k in pairs(tbl) do
		tbl[k] = nil
	end

	tableCache[tbl] = true
end

--- @param template string
--- @return LibLog-1.0.MessageTemplate
local function GetMessageTemplate(template)
	local result = templateCache[template]
	if result ~= nil then
		return result
	end

	result = {
		--- @diagnostic disable-next-line: assign-type-mismatch
		message = nil,
		properties = {}
	}

	result.message = string.gsub(template, "{(.-)}", function(key)
		table.insert(result.properties, key)
		return "%s"
	end)

	templateCache[template] = result

	return result
end

--- @param ... unknown
--- @return integer
--- @return unknown[]
local function PackVarargs(...)
	local count = select("#", ...)
	local result = AcquireCachedTable()

	for i = 1, count do
		result[i] = select(i, ...)
	end

	return count, result
end

--- @param ... unknown
--- @return integer
--- @return unknown[]
local function GetValues(...)
	local n = select("#", ...)
	if n ~= 1 then
		return PackVarargs(...)
	end

	local func = select(1, ...)
	if type(func) ~= "function" then
		return PackVarargs(...)
	end

	local count, callback = PackVarargs(xpcall(func, ErrorHandler))

	if callback[1] then
		table.remove(callback, 1)
		return count - 1, callback
	end

	return 0, AcquireCachedTable()
end

--- @param message LibLog-1.0.LogMessage
local function ChatFrameSink(message)
	local frame = DEFAULT_CHAT_FRAME

	--- @type string[]
	local prefix

	if message.level <= LibLog.LogLevel.DEBUG then
		prefix = {
			"|c",
			LibLog.colorScheme[message.level],
			date("%H:%M:%S", message.time) --[[@as string]],
			" ",
			LibLog.labels[message.level],
			" ",
			message.addon,
			":",
			"|r"
		}
	else
		prefix = {
			"|c",
			LibLog.colorScheme[message.level],
			LibLog.labels[message.level],
			" ",
			message.addon,
			":",
			"|r"
		}
	end

	if frame then
		frame:AddMessage(table.concat(prefix, "") .. " " .. message.message)
	end
end

--- @param string string
--- @param color string
--- @return string
local function Colorize(string, color)
	return "|c" .. color .. string .. "|r"
end

--- @param value unknown
--- @return string
local function ColorizeValue(value)
	local valueType = type(value)

	if valueType == "string" and C_EventUtils.IsEventValid(value) then
		return Colorize(value, LibLog.colorScheme["event"])
	end

	local color = LibLog.colorScheme[valueType] or LibLog.colorScheme["string"]
	return Colorize(tostring(value), color)
end

--- @param value unknown
--- @return string
local function Destructure(value)
	local T_COLOR = LibLog.colorScheme["table"]
	local K_COLOR = LibLog.colorScheme["tableKey"]

	local MAX_DEPTH = 5

	--- @type table<table, boolean>
	local visited = AcquireCachedTable()

	--- @param o unknown
	--- @param depth integer
	--- @return string
	local function DestructureImpl(o, depth)
		if depth >= MAX_DEPTH or type(o) ~= "table" or visited[o] then
			return ColorizeValue(o)
		end

		--- @type string[]
		local buffer = AcquireCachedTable()
		local first = true

		visited[o] = true

		for k, v in pairs(o) do
			local destructured = DestructureImpl(v, depth + 1)

			if destructured ~= nil then
				table.insert(buffer, Colorize(tostring(k), K_COLOR))
				table.insert(buffer, destructured)

				first = false
			end
		end

		visited[o] = nil

		if first then
			ReleaseCachedTable(buffer)
			return Colorize("{}", T_COLOR)
		end

		table.insert(buffer, 1, Colorize("{", T_COLOR))
		table.insert(buffer, Colorize("}", T_COLOR))

		local result = table.concat(buffer, " ")

		ReleaseCachedTable(buffer)

		return result
	end

	local result = DestructureImpl(value, 1)

	ReleaseCachedTable(visited)
	return result
end

--- @param addon? string
--- @param message LibLog-1.0.MessageTemplate
--- @param values unknown[]
--- @return table<string, unknown>
local function PopulateMessageProperties(addon, message, values)
	if addon == nil then
		return {}
	end

	--- @type table<string, unknown>
	local result = {}

	local global = LibLog.properties[addon]
	if global ~= nil then
		for _, v in pairs(global) do
			if v.isCallback then
				local success, value = xpcall(v.value, ErrorHandler)

				if success then
					result[v.name] = value
				end
			else
				result[v.name] = v.value
			end
		end
	end

	for i = 1, #message.properties do
		result[message.properties[i]] = values[i]
	end

	return result
end

--- @param name? string
--- @param level LibLog-1.0.LogLevel
--- @return boolean
local function IsLogAllowed(name, level)
	local addonLevel = LibLog.levels[name]

	if addonLevel ~= nil then
		return level >= addonLevel
	end

	return level >= minLogLevel
end

--- Log a VRB message. Verbose logs should be used for high-frequency logs or low-level data. For example, raw calculations or other raw data.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogVerbose(template, ...)` to immediately exit the running function with a `nil`
--- value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogVerbose(template, ...)
	return LibLog:Log(self.name, LibLog.LogLevel.VERBOSE, template, ...)
end

--- Log a DBG message. Debug logs should be used for developers to verify code paths, state changes, or event registration during active
--- development and testing.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogDebug(template, ...)` to immediately exit the running function with a `nil` value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogDebug(template, ...)
	return LibLog:Log(self.name, LibLog.LogLevel.DEBUG, template, ...)
end

--- Log an INF message. Info logs shoud be used for general status updates and milestones. Generally when following the happy path of your code
--- to indicate the addon is working. For example, successful loading, profile changes, or user-triggered actions.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogInfo(template, ...)` to immediately exit the running function with a `nil` value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogInfo(template, ...)
	return LibLog:Log(self.name, LibLog.LogLevel.INFO, template, ...)
end

--- Log a WRN message. Warning logs should be the result of user error or other non-breaking issues. For example, optional settings are missing
--- or an input is invalid.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogWarning(template, ...)` to immediately exit the running function with a `nil`
--- value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogWarning(template, ...)
	return LibLog:Log(self.name, LibLog.LogLevel.WARNING, template, ...)
end

--- Log an ERR message. Error logs should indicate a high severity logic failure. For example, an API returns unexpected data. An error likely
--- indicates a bug that should be fixed, though execution can continue.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogError(template, ...)` to immediately exit the running function with a `nil` value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogError(template, ...)
	return LibLog:Log(self.name, LibLog.LogLevel.ERROR, template, ...)
end

--- Log a FTL message, and submit the error to the error handler. Fatal logs are the highest severity, and should be used sparringly, when
--- execution **cannot** continue and must be halted because continuing may lead to data corruption or unrecoverable states. For example, misssing libraries
--- or broken saved variables.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogFatal(template, ...)` to immediately exit the running function. Though this
--- function will trigger a Lua error pop-up when enabled by the user.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogFatal(template, ...)
	return LibLog:Log(self.name, LibLog.LogLevel.FATAL, template, ...)
end

--- Push a new property onto the stack, the value of this property will be present within the context of all further logs, until it is popped.
---
--- @param name string
--- @param value unknown|function
function Logger:PushLogProperty(name, value)
	if self.name == nil then
		return
	end

	--- @type LibLog-1.0.Property
	local property = {
		name = name,
		value = value,
		isCallback = type(value) == "function"
	}

	LibLog.properties[self.name] = LibLog.properties[self.name] or {}
	LibLog.properties[self.name][name] = property
end

--- Pop properties that were previously pushed.
---
--- @param ... string
function Logger:PopLogProperty(...)
	if self.name == nil then
		return
	end

	local properties = LibLog.properties[self.name]
	if properties == nil then
		return
	end

	local n = select("#", ...)
	for i = 1, n do
		local name = select(i, ...)
		properties[name] = nil
	end
end

--- Create a closure where all logs contain the given properties.
---
--- @param properties table<string, unknown>
--- @param closure fun()
function Logger:WithLogContext(properties, closure)
	for k, v in pairs(properties) do
		self:PushLogProperty(k, v)
	end

	local ok, err = pcall(closure)

	for k in pairs(properties) do
		self:PopLogProperty(k)
	end

	if not ok then
		error(err, 2)
	end
end

--- Set the log level for the given addon.
---
--- This will invoke a callback function on the addon to notify its log level has changed, allowing the addon to maintain its own saved variables.
---
--- @param level? LibLog-1.0.LogLevel The log level to set.
function Logger:SetLogLevel(level, addon)
	--- @diagnostic disable-next-line: undefined-field
	addon = addon or self.name
	if addon == nil then
		return
	end

	LibLog.levels[addon] = level
end

--- Set the log level for the given addon using a configuration table.
---
--- @param configTable table A configuration table to retrieve the current log level from, usually your saved variables.
function Logger:SetLogLevelFromConfigTable(configTable)
	if self.name == nil then
		return
	end

	local level = configTable[LibLog.configKey]

	if level ~= nil then
		self:SetLogLevel(level)
	end
end

--- Get the current log level for the given addon.
function Logger:GetLogLevel()
	return LibLog.levels[self.name] or minLogLevel
end

--- Create an AceGUI option table which can manipulate the log level of the given addon.
---
--- @param configTable table A configuration table to store and retrieve current log level values from, usually your saved variables.
function Logger:GetLogLevelOptionObject(configTable)
	return {
		name = L.level,
		desc = L.level_desc,
		type = "select",
		style = "dropdown",
		values = function()
			local result = {}

			for k, v in pairs(LibLog.LogLevel) do
				result[v] = k
			end

			return result
		end,
		sorting = function()
			local result = {}

			for _, v in pairs(LibLog.LogLevel) do
				table.insert(result, v)
			end

			table.sort(result, function(l, r)
				return l < r
			end)

			return result
		end,
		get = function()
			return configTable[LibLog.configKey] or self:GetLogLevel()
		end,
		set = function(_, value)
			self:SetLogLevel(value)
			configTable[LibLog.configKey] = value
		end
	}
end

--- Register an external sink to replicate the logging stream.
---
--- @param name string
--- @param callback fun(message: LibLog-1.0.LogMessage)
function LibLog:RegisterSink(name, callback)
	assert(type(callback) == "function", "Cannot register a non-function log sink")

	LibLog.sinks[name] = {
		callback = callback,
		enabled = true
	}
end

--- Enable a sink.
---
--- @param name string
function LibLog:EnableSink(name)
	local sink = LibLog.sinks[name]

	if sink ~= nil then
		sink.enabled = false
	end
end

--- Disable a sink, preventing it from receiving new messages until re-enabled.
---
--- @param name string
function LibLog:DisableSink(name)
	local sink = LibLog.sinks[name]

	if sink ~= nil then
		sink.enabled = false
	end
end

--- Get all registered, or all enabled sinks.
---
--- @param enabledOnly? boolean
--- @return string[]
function LibLog:GetSinks(enabledOnly)
	--- @type string[]
	local result = {}

	for name, sink in pairs(LibLog.sinks) do
		if not enabledOnly or (enabledOnly and sink.enabled) then
			table.insert(result, name)
		end
	end

	return result
end

--- Embed `LibLog-1.0` into the target object, making several logging functions available for use.
---
--- @generic T : table
--- @param target T The target object.
--- @return T
function LibLog:Embed(target)
	for k, v in pairs(Logger) do
		target[k] = v
	end

	LibLog.embeds[target] = true

	return target
end

--- Log a message to the console.
---
--- Any log level other than `FATAL` will be printed to the standard output, a log level of `FATAL` will additionally also be submitted to the error handler,
--- and halt execution of the current code path.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogFatal(...)` to immediately exit the running function when required.
---
--- @private
--- @param addon? string The name of the addon.
--- @param level LibLog-1.0.LogLevel The log level to log with.
--- @param template string The message template.
--- @param ... any The values to log.
--- @return unknown
function LibLog:Log(addon, level, template, ...)
	local isAllowed = IsLogAllowed(addon, level)
	local isFatal = level == LibLog.LogLevel.FATAL

	if not isAllowed and not isFatal then
		return nil
	end

	local message = GetMessageTemplate(template)
	local properties = AcquireCachedTable() --[[@as string[] ]]
	local _, values = GetValues(...)

	for i = 1, #message.properties do
		local value = values[i]
		properties[i] = Destructure(value)
	end

	local parsedMessage = string.format(message.message, unpack(properties))

	if isAllowed then
		local now = time()

		if now ~= currentTime then
			currentTime = now
			currentSequenceId = 1
		else
			currentSequenceId = currentSequenceId + 1
		end

		--- @type LibLog-1.0.LogMessage
		local result = {
			message = parsedMessage,
			addon = addon,
			level = level,
			time = currentTime,
			sequenceId = currentSequenceId,
			properties = PopulateMessageProperties(addon, message, values)
		}

		ChatFrameSink(result)

		for _, sink in pairs(LibLog.sinks) do
			if sink.enabled then
				xpcall(sink.callback, ErrorHandler, result)
			end
		end
	end

	ReleaseCachedTable(values)
	ReleaseCachedTable(properties)

	if isFatal then
		error(parsedMessage, 3)
	end

	return nil
end

--- Run a test suite, showcasing all functionality.
---
--- @private
function LibLog:TestSuite()
	local Addon = LibLog:Embed({
		name = "TestSuite"
	})

    Addon:SetLogLevel(LibLog.LogLevel.INFO)
    Addon:LogVerbose("HIDDEN: Verbose")
    Addon:LogDebug("HIDDEN: Debug")
    Addon:LogInfo("VISIBLE: Info")
    Addon:LogWarning("VISIBLE: Warning")

    Addon:LogInfo("string={stringValue}, number={numberValue}, boolean={booleanValue}, nil={nilValue}, plain text", "string", 123.456, true, nil)
    Addon:LogInfo("Complex: {complexTable}", {
        sub = { a = 1, b = { "deep" } },
        empty = {},
        list = { 10, nil, 30 }
    })
    Addon:LogInfo("Empty Top-Level: {emptyTable}", {})

    local circular = { name = "Self" }
    circular.child = circular
    Addon:LogInfo("Circular: {circularTable}", circular)
	Addon:LogInfo("Too deep: {tooDeepTable}", { two = { three = { four = { five = { six = { "test" }}}}}})

	Addon:LogInfo("{player} is {online} with {hp} HP", "Arthas", true, 50.5)
	Addon:LogInfo("With more parameters than arguments: {player} is {online} with {hp} HP", "Arthas")
	Addon:LogInfo("With more arguments than parameters: {player} is {online} with {hp} HP", "Arthas", true, 50.5, "extra", 0.2, true)
	Addon:LogInfo("{cpu} at {time}", function()
		return "0.01ms", GetTime()
	end)

	LibLog.embeds[Addon] = nil
	LibLog.levels[Addon.name] = nil
end

for target in pairs(LibLog.embeds) do
	LibLog:Embed(target)
end
