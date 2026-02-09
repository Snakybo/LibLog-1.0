-- LibLog-1.0, a logging library for World of Warcraft.
-- Copyright (C) 2026 Kevin Krol

-- This library is free software; you can redistribute it and/or
-- modify it under the terms of the GNU Lesser General Public
-- License as published by the Free Software Foundation; either
-- version 2.1 of the License, or (at your option) any later version.

-- This library is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- Lesser General Public License for more details.

-- You should have received a copy of the GNU Lesser General Public
-- License along with this library; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
-- USA

-- To use this library, embed it into your addon, either automatically using AceAddon-3.0, or manually:
--
--   MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibLog-1.0")
-- -or-
--   LibStub("LibLog-1.0"):Embed(MyAddon)
--
-- Afterwards, you will be able to log messages using:
--
--   MyAddon:LogFatal(...)
--   MyAddon:LogError(...)
--   MyAddon:LogWarning(...)
--   MyAddon:LogInfo(...)
--   MyAddon:LogDebug(...)
--   MyAddon:LogVerbose(...)
--
-- The arguments can be any number of values, they will be seperated using a whitespace. A value can be of any type, for example:
--
--   MyAddon:LogInfo("Received", true, false, nil, 1.356)
--   -- INF MyAddon: Received true false nil 1.356
--
-- You can manipulate the current log level using:
--
--   MyAddon:SetLogLevel(LibLog.LogLevel.ERROR)
--   MyAddon:GetLogLevel()
--
-- When using AceConfigDialog-3.0, you can almost seamlessly integrate a setting for the log level into your addons settings panel, simply:
--
--   {
--     logLevel = MyAddon:GetLogLevelOptionObject(MyAddon.db.global)
--   }
--
-- The second paramter refers to the configuration object, usually a table within your saved variables.
-- For more complicated setups where you wish to have control over the option, you can use a mixin:
--
--   {
--     logLevel = Mixin(MyAddon:GetLogLevelOptionObject(MyAddon.db.global), {
--       order = 200
--     })
--   }
--
-- To initialize the log level for your addon upon load, you can use the following:
--
--   function MyAddon:OnInitialize()
--     MyAddon.db = LibStub("AceDB-3.0"):New("MyAddonDB")
--
--     self:SetLogLevelFromConfigTable(MyAddon.db.global)
--   end
--
-- LibLog-1.0 works best when your addon object has a `name` field. When using AceAddon-3.0, this is already the case, however when embedding manually, it is
-- recommended to set a `name` field to the name of your addon, otherwise LibLog-1.0 cannot determine the source of the log message, and will have to mark it as
-- <unknown>.
--
-- Logging methods also allow for a callback function, this is a special case which can be used to improve performance, since filtered out log levels are only
-- evaluated after the message contents have been computed it's possible for your addon to perform complex logic for nothing. Specifying a callback function as
-- the first and only parameter, allows you to perform that logic on-demand, and ensure it does not impact performance when logs are disabled.
--
--   MyAddon:LogVerbose(function()
--     local result = {}
--
--     for i = 1, GetNumGroupMembers() do
--       table.insert(result, UnitName("party" .. i))
--     end
--
--     return result
--   end)
--
-- -or-
--
--   MyAddon:LogInfo(function()
--     return 1, true, "UNIT_HEALTH"
--   end)
--
-- The callback can return either a table, or varargs.
--
-- Since log levels can be modified externally, by, for example, an addon that manages log levels per addon, there is a callback that can be used to be notified
-- when your log level has changed.
--
--   function MyAddon:OnLogLevelChanged(level)
--
-- Within this callback, you can do two things, either manually update your configuration object, or return it for automatic handling.
--
--   function MyAddon:OnLogLevelChanged(level)
--     MyAddon.db.global[LibLog.CONFIG_KEY] = level
--   end
--
--   function MyAddon:OnLogLevelChanged(level)
--     return MyAddon.db.global
--   end
--
-- It's also possible to register a custom log sink, this is useful if you want to capture either your own, or all log events as they happen, for example,
-- to show them in a custom logging window.
--
--   LibLog:RegisterSink(function(addon, level, prefix, message)
--     print(prefix .. " " .. message)
--   end

if LibStub == nil then
	error("LibLog-1.0 requires LibStub")
end

--- @class LibLog-1.0
local LibLog = LibStub:NewLibrary("LibLog-1.0", 6)
if LibLog == nil then
	return
end

--- @alias LogSink fun(addon?: string, level: LogLevel, prefix: string, message: string)

LibLog.UNKNOWN = "Unk"
LibLog.CONFIG_KEY = "logLevel"
LibLog.CALLBACK_NAME = "OnLogLevelChanged"

--- @enum LogLevel
LibLog.LogLevel = {
	NONE = 0,
	FATAL = 1,
	ERROR = 2,
	WARNING = 3,
	INFO = 4,
	DEBUG = 5,
	VERBOSE = 6
}

--- The default minimum log level. If not overwritten by an addon, this will be used.
LibLog.minLevel = LibLog.minLevel or LibLog.LogLevel.INFO

--- Whether the default chat sink is enabled.
LibLog.enableDefaultSink = LibLog.enableDefaultSink or true

--- @type table<table, boolean>
LibLog.embeds = LibLog.embeds or {}

--- @type table<string, LogLevel>
LibLog.levels = LibLog.levels or {}

--- @type LogSink[]
LibLog.sinks = LibLog.sinks or {}

LibLog.levelNames = {
	[LibLog.LogLevel.FATAL] = "FTL",
	[LibLog.LogLevel.ERROR] = "ERR",
	[LibLog.LogLevel.WARNING] = "WRN",
	[LibLog.LogLevel.INFO] = "INF",
	[LibLog.LogLevel.DEBUG] = "DBG",
	[LibLog.LogLevel.VERBOSE] = "VRB"
}

local L = {
	level = "Log level",
	level_desc = "Select the logging level for this addon. Select 'NONE' to completely disable logging.\n\nLower values mean more messages get logged, where 'VERBOSE' logs everything."
}

local colors = {
	[LibLog.LogLevel.FATAL] = "ffff0000",
	[LibLog.LogLevel.ERROR] = "ffcc6666",
	[LibLog.LogLevel.WARNING] = "fff0c674",
	[LibLog.LogLevel.INFO] = "ff81a2be",
	[LibLog.LogLevel.DEBUG] = "ff707880",
	[LibLog.LogLevel.VERBOSE] = "ff707880"
}

local typeColors = {
	["table"] = "ff969896",
	["string"] = "ffc5c8c6",
	["number"] = "ff8abeb7",
	["boolean"] = "ff8abeb7",
	["nil"] = "bb5f819d"
}

local miscColors = {
	["key"] = "ffde935f",
	["evt"] = "ffb48ead",
	["empty"] = "ff4c566a"
}

local mixins = {
	"LogVerbose",
	"LogDebug",
	"LogInfo",
	"LogWarning",
	"LogError",
	"LogFatal",
	"Log",
	"SetLogLevel",
	"SetLogLevelFromConfigTable",
	"GetLogLevel",
	"GetLogLevelOptionObject"
}

--- @type fun(): table
local AcquireTable

--- @type fun(tbl: table)
local ReleaseTable

do
	local pool = {}

	AcquireTable = function()
		local result = next(pool)

		if result ~= nil then
			pool[result] = nil
			return result
		end

		return {}
	end

	ReleaseTable = function(tbl)
		for k in pairs(tbl) do
			tbl[k] = nil
		end

		pool[tbl] = true
	end
end

--- @param ... unknown
--- @return integer
--- @return unknown[]
local function Pack(...)
	local count = select("#", ...)
	local result = AcquireTable()

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
		return Pack(...)
	end


	local func = select(1, ...)
	if type(func) ~= "function" then
		return Pack(...)
	end

	local count, callback = Pack(xpcall(func, geterrorhandler()))

	if callback[1] then
		table.remove(callback, 1)
		count = count - 1

		if count == 1 and type(callback[1]) == "table" then
			return #callback[1], callback[1]
		end
	end

	return count, callback
end

--- @param prefix string
--- @param message string
local function DefaultChatFrameSink(_, _, prefix, message)
	local frame = DEFAULT_CHAT_FRAME

	if frame then
		frame:AddMessage(prefix .. " " .. message)
	end
end

--- @param string string
--- @param color string
--- @return string
local function Colorize(string, color)
	return "|c" .. color .. string .. "|r"
end

--- @param value any
--- @return string
local function ColorizeValue(value)
	local valueType = type(value)

	if valueType == "string" and C_EventUtils.IsEventValid(value) then
		return Colorize(value, miscColors["evt"])
	end

	local color = typeColors[valueType] or typeColors["string"]
	return Colorize(tostring(value), color)
end

--- @param value any
local function Destructure(value)
	local T_COLOR = typeColors["table"]
	local K_COLOR = miscColors["key"]
	local E_COLOR = miscColors["empty"]

	local MAX_DEPTH = 5

	--- @type table<table, boolean>
	local visited = AcquireTable()

	--- @param o any
	--- @param depth integer
	--- @return string?
	local function DestructureImpl(o, depth)
		if depth >= MAX_DEPTH or type(o) ~= "table" or visited[o] then
			return ColorizeValue(o)
		end

		--- @type string[]
		local buffer = AcquireTable()
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
			ReleaseTable(buffer)
			return Colorize("<empty table>", E_COLOR)
		end

		table.insert(buffer, 1, Colorize("{", T_COLOR))
		table.insert(buffer, Colorize("}", T_COLOR))

		local result = table.concat(buffer, " ")

		ReleaseTable(buffer)
		return result
	end

	local result = DestructureImpl(value, 1)

	ReleaseTable(visited)
	return result
end

--- @param addon string
--- @param level? LogLevel
local function NotifyLogLevelChanged(addon, level)
	local function Notify(obj)
		local cb = obj[LibLog.CALLBACK_NAME]

		if cb ~= nil then
			local success, configTable = xpcall(cb, geterrorhandler(), obj, level)

			if success and type(configTable) == "table" then
				configTable[LibLog.CONFIG_KEY] = level
			end
		end
	end

	for k in pairs(LibLog.embeds) do
		if k.name == addon then
			Notify(k)
			break
		end
	end
end

--- @param name? string
--- @param level LogLevel
--- @return boolean
local function IsLogAllowed(name, level)
	local addonLevel = LibLog.levels[name]

	if addonLevel ~= nil then
		return level <= addonLevel
	end

	return level <= LibLog.minLevel
end

--- @param name? string
--- @param level LogLevel
local function GetPrefix(name, level)
	local prefix

	if level >= LibLog.LogLevel.DEBUG then
		prefix = {
			"|c",
			colors[level],
			string.format("%.3f", GetTimePreciseSec()),
			" ",
			LibLog.levelNames[level],
			" ",
			name or LibLog.UNKNOWN,
			":",
			"|r"
		}
	else
		prefix = {
			"|c",
			colors[level],
			LibLog.levelNames[level],
			" ",
			name or LibLog.UNKNOWN,
			":",
			"|r"
		}
	end

	return table.concat(prefix, "")
end

--- Log a VRB message to the console. Verbose logs should be used for high-frequency logs or low-level data. For example, raw calculations or other raw data.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogVerbose(...)` to immediately exit the running function with a `nil` value.
---
--- @param ... any The values to log.
--- @return unknown
function LibLog:LogVerbose(...)
	return self:Log(LibLog.LogLevel.VERBOSE, ...)
end

--- Log a DBG message to the console. Debug logs should be used for developers to verify code paths, state changes, or event registration during active
--- development and testing.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogDebug(...)` to immediately exit the running function with a `nil` value.
---
--- @param ... any The values to log.
--- @return unknown
function LibLog:LogDebug(...)
	return self:Log(LibLog.LogLevel.DEBUG, ...)
end

--- Log an INF message to the console. Info logs shoud be used for general status updates and milestones. Generally when following the happy path of your code
--- to indicate the addon is working. For example, successful loading, profile changes, or user-triggered actions.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogInfo(...)` to immediately exit the running function with a `nil` value.
---
--- @param ... any The values to log.
--- @return unknown
function LibLog:LogInfo(...)
	return self:Log(LibLog.LogLevel.INFO, ...)
end

--- Log a WRN message to the console. Warning logs should be the result of user error or other non-breaking issues. For example, optional settings are missing
--- or an input is invalid.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogWarning(...)` to immediately exit the running function with a `nil` value.
---
--- @param ... any The values to log.
--- @return unknown
function LibLog:LogWarning(...)
	return self:Log(LibLog.LogLevel.WARNING, ...)
end

--- Log an ERR message to the console. Error logs should indicate a high severity logic failure. For example, an API returns unexpected data. An error likely
--- indicates a bug that should be fixed, though execution can continue.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogError(...)` to immediately exit the running function with a `nil` value.
---
--- @param ... any The values to log.
--- @return unknown
function LibLog:LogError(...)
	return self:Log(LibLog.LogLevel.ERROR, ...)
end

--- Log a FTL message to the console, and submit the error to the error handler. Fatal logs are the highest severity, and should be used sparringly, when
--- execution **cannot** continue and must be halted because continuing may lead to data corruption or unrecoverable states. For example, misssing libraries
--- or broken saved variables.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogFatal(...)` to immediately exit the running function. Though this function will
--- trigger a Lua error pop-up when enabled by the user.
---
--- @param ... any The values to log.
--- @return unknown
function LibLog:LogFatal(...)
	return self:Log(LibLog.LogLevel.FATAL, ...)
end

--- Log a message to the console.
---
--- Any log level other than `FATAL` will be printed to the standard output, a log level of `FATAL` will additionally also be submitted to the error handler,
--- and halt execution of the current code path.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogFatal(...)` to immediately exit the running function when required.
---
--- @private
--- @param level LogLevel The log level to log with.
--- @param ... any The values to log.
--- @return unknown
function LibLog:Log(level, ...)
	--- @diagnostic disable-next-line: undefined-field
	local name = self.name

	local isAllowed = IsLogAllowed(name, level)
	local isFatal = level == LibLog.LogLevel.FATAL

	if not isAllowed and not isFatal then
		return nil
	end

	local message = AcquireTable()
	local _, values = GetValues(...)

	for _, value in pairs(values) do
		table.insert(message, Destructure(value))
	end

	local str = table.concat(message, " ")

	ReleaseTable(message)
	ReleaseTable(values)

	if isAllowed then
		local prefix = GetPrefix(name, level)

		if LibLog.enableDefaultSink then
			DefaultChatFrameSink(name, level, prefix, str)
		end

		for i = 0, #LibLog.sinks do
			pcall(LibLog.sinks[i], name, level, prefix, str)
		end
	end

	if isFatal then
		error(str, 3)
	end

	return nil
end

--- Register an external sink to replicate the logging stream.
---
--- @param sink LogSink
function LibLog:RegisterSink(sink)
	assert(type(sink) == "function", "Cannot register a non-function log sink")
	table.insert(LibLog.sinks, sink)
end

--- Set the log level for the given addon.
---
--- This will invoke a callback function on the addon to notify its log level has changed, allowing the addon to maintain its own saved variables.
---
--- @param level? LogLevel The log level to set.
--- @param addon? string The name of the addon to manipulate. If `nil`, it will attempt to retrieve a name from `self.name`.
function LibLog:SetLogLevel(level, addon)
	--- @diagnostic disable-next-line: undefined-field
	addon = addon or self.name
	if addon == nil then
		return
	end

	LibLog.levels[addon] = level

	NotifyLogLevelChanged(addon, level)
end

--- Set the log level for the given addon using a configuration table.
---
--- @param configTable table A configuration table to retrieve the current log level from, usually your saved variables.
--- @param addon string? The name of the addon to manipulate. If `nil`, it will attempt to retrieve a name from `self.name`.
function LibLog:SetLogLevelFromConfigTable(configTable, addon)
	--- @diagnostic disable-next-line: undefined-field
	addon = addon or self.name
	if addon == nil then
		return
	end

	local level = configTable[LibLog.CONFIG_KEY]

	if level ~= nil then
		self:SetLogLevel(level, addon)
	end
end

--- Get the current log level for the given addon.
---
--- @param addon string? The name of the addon to retrieve the log level for. If `nil`, it will attempt to retrieve a name from `self.name`.
function LibLog:GetLogLevel(addon)
	--- @diagnostic disable-next-line: undefined-field
	addon = addon or self.name
	return LibLog.levels[addon] or LibLog.minLevel
end

--- Create an AceGUI option table which can manipulate the log level of the given addon.
---
--- @param configTable table A configuration table to store and retrieve current log level values from, usually your saved variables.
--- @param addon? string The name of the addon to manipulate. If `nil`, it will attempt to retrieve a name from `self.name`.
function LibLog:GetLogLevelOptionObject(configTable, addon)
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

			table.sort(result, function(l, r) return l < r end)

			return result
		end,
		get = function()
			return configTable[LibLog.CONFIG_KEY] or LibLog:GetLogLevel(addon)
		end,
		set = function(_, value)
			LibLog:SetLogLevel(value, addon)
			configTable[LibLog.CONFIG_KEY] = value
		end
	}
end

--- Embed `LibLog-1.0` into the target object, making several logging functions available for use.
---
--- @generic T : table
--- @param target T The target object.
--- @return T
function LibLog:Embed(target)
	for _, v in pairs(mixins) do
		target[v] = self[v]
	end

	LibLog.embeds[target] = true

	return target
end

for target in pairs(LibLog.embeds) do
	LibLog:Embed(target)
end
