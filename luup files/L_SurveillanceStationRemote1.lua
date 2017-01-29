--[[
  This file is part of the plugin Edisio Gateway.
  https://github.com/vosmont/Vera-Plugin-SurveillanceStationRemote
  Copyright (c) 2016 Vincent OSMONT
  This code is released under the MIT License, see LICENSE.
--]]

module("L_SurveillanceStationRemote1", package.seeall)

-- Imports
local status, json = pcall( require, "dkjson" )
if ( type( json ) ~= "table" ) then
	-- UI5
	json = require( "json" )
end

--local http = require( "socket.http" )
local ltn12 = require( "ltn12" )
local Url = require( "socket.url" )


-- **************************************************
-- Plugin constants
-- **************************************************

_NAME = "SurveillanceStationRemote"
_DESCRIPTION = "A remote for Synology Surveillance Station"
_VERSION = "0.7"

local REQUEST_TIMEOUT = 10
local NB_MAX_TRY = 2
local MIN_POLL_INTERVAL = 10
local MIN_POLL_INTERVAL_AFTER_ERROR = 60
local MIN_INTERVAL_BETWEEN_REQUESTS = 5

-- **************************************************
-- Constants
-- **************************************************

-- This table defines all device variables that are used by the plugin
-- Each entry is a table of 4 elements:
-- 1) the service ID
-- 2) the variable name
-- 3) true if the variable is not updated when the value is unchanged
-- 4) variable that is used for the timestamp
local VARIABLE = {
	SWITCH_POWER = { "urn:upnp-org:serviceId:SwitchPower1", "Status", true },
	-- Communication failure
	COMM_FAILURE = { "urn:micasaverde-com:serviceId:HaDevice1", "CommFailure", false, "COMM_FAILURE_TIME" },
	COMM_FAILURE_TIME = { "urn:micasaverde-com:serviceId:HaDevice1", "CommFailureTime", true },
	-- Surveilance Station Remote
	PLUGIN_VERSION = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "PluginVersion", true },
	DEBUG_MODE = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "DebugMode", true },
	PROTOCOL = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "Protocol", true },
	HOST = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "Host", true },
	PORT = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "Port", true },
	USERNAME = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "UserName", true },
	PASSWORD = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "Password", true },
	SESSION_ID = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "SessionId", true },
	LAST_MESSAGE = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "LastMessage", true },
	LAST_ERROR = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "LastError", true },
	LAST_UPDATE = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "LastUpdate", true },
	RECORD = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "Record", true },
	NB_MAX_TRY = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "NbMaxTry", true },
	REQUEST_TIMEOUT = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "RequestTimeout", true },
	POLL_SETTINGS = { "urn:upnp-org:serviceId:SurveillanceStationRemote1", "PollSettings", true }
}


-- Synology API Error Code
local API_ERROR_CODE = {
	["common"] = {
		[100] = { "Unknown error", false },
		[101] = { "Invalid parameters", false },
		[102] = { "API does not exist", true },
		[103] = { "Method does not exist", true },
		[104] = { "This API version is not supported", true },
		[105] = { "Insufficient user privilege", true },
		[106] = { "Connection time out", false },
		[107] = { "Multiple login detected", false },
		[117] = { "Need manager rights for operation", true },
		[400] = { "Execution failed", false },
		[401] = { "Parameter invalid", false }
	},
	["SYNO.API.Auth"] = {
		[101] = { "The account parameter is not specified", true },
		[400] = { "Invalid user or password", true },
		[401] = { "Guest or disabled account", true },
		[402] = { "Permission denied", false },
		[403] = { "One time password not specified", true },
		[404] = { "One time password authenticate failed", true }
	},
	["SYNO.SurveillanceStation.Camera"] = {
		[402] = { "Camera disabled", false },
		[407] = { "CMS closed", false }
	},
	["SYNO.SurveillanceStation.ExternalEvent"] = {
		-- ???
	},
	["SYNO.SurveillanceStation.ExternalRecording"] = {
		[402] = { "Camera disabled", false }
	},
	["SYNO.SurveillanceStation.PTZ"] = {
		[402] = { "Camera disabled", false }
	}
}


-- **************************************************
-- Plugin variables
-- **************************************************

local g_parentDeviceId
local g_params = {}

-- **************************************************
-- UI compatibility
-- **************************************************

-- Update static JSON file
function updateStaticJSONFile( lul_device, pluginName )
	local isUpdated = false
	if ( luup.version_branch ~= 1 ) then
		luup.log( "ERROR - Plugin '" .. pluginName .. "' - checkStaticJSONFile : don't know how to do with this version branch " .. tostring( luup.version_branch ), 1 )
	elseif ( luup.version_major > 5 ) then
		local currentStaticJsonFile = luup.attr_get( "device_json", lul_device )
		local expectedStaticJsonFile = "D_" .. pluginName .. "_UI" .. tostring( luup.version_major ) .. ".json"
		if (currentStaticJsonFile ~= expectedStaticJsonFile) then
			luup.attr_set( "device_json", expectedStaticJsonFile, lul_device )
			isUpdated = true
		end
	end
	return isUpdated
end


-- **************************************************
-- Table functions
-- **************************************************

-- Merges (deeply) the contents of one table (t2) into another (t1)
local function table_extend( t1, t2 )
	if ( ( t1 == nil ) or ( t2 == nil ) ) then
		return
	end
	for key, value in pairs( t2 ) do
		if ( type( value ) == "table" ) then
			if ( type( t1[key] ) == "table" ) then
				t1[key] = table_extend( t1[key], value )
			else
				t1[key] = table_extend( {}, value )
			end
		elseif ( value ~= nil ) then
			t1[key] = value
		end
	end
	return t1
end

local table = table_extend( {}, table ) -- do not pollute original "table"
do -- Extend table
	table.extend = table_extend

	-- Checks if a table contains the given item.
	-- Returns true and the key / index of the item if found, or false if not found.
	function table.contains( t, item )
		for k, v in pairs( t ) do
			if ( v == item ) then
				return true, k
			end
		end
		return false
	end

	-- Checks if table contains all the given items (table).
	function table.containsAll( t1, items )
		if ( ( type( t1 ) ~= "table" ) or ( type( t2 ) ~= "table" ) ) then
			return false
		end
		for _, v in pairs( items ) do
			if not table.contains( t1, v ) then
				return false
			end
		end
		return true
	end

	-- Appends the contents of the second table at the end of the first table
	function table.append( t1, t2, noDuplicate )
		if ( ( t1 == nil ) or ( t2 == nil ) ) then
			return
		end
		local table_insert = table.insert
		table.foreach(
			t2,
			function ( _, v )
				if ( noDuplicate and table.contains( t1, v ) ) then
					return
				end
				table_insert( t1, v )
			end
		)
		return t1
	end

	-- Extracts a subtable from the given table
	function table.extract( t, start, length )
		if ( start < 0 ) then
			start = #t + start + 1
		end
		length = length or ( #t - start + 1 )

		local t1 = {}
		for i = start, start + length - 1 do
			t1[#t1 + 1] = t[i]
		end
		return t1
	end

	function table.concatChar( t )
		local res = ""
		for i = 1, #t do
			res = res .. string.char( t[i] )
		end
		return res
	end

	-- Concatenates a table of numbers into a string with Hex separated by the given separator.
	function table.concatHex( t, sep, start, length )
		sep = sep or "-"
		start = start or 1
		if ( start < 0 ) then
			start = #t + start + 1
		end
		length = length or ( #t - start + 1 )
		local s = _toHex( t[start] )
		if ( length > 1 ) then
			for i = start + 1, start + length - 1 do
				s = s .. sep .. _toHex( t[i] )
			end
		end
		return s
	end

end

-- **************************************************
-- String functions
-- **************************************************

local string = table_extend( {}, string ) -- do not pollute original "string"
do -- Extend string
	-- Pads string to given length with given char from left.
	function string.lpad( s, length, c )
		s = tostring( s )
		length = length or 2
		c = c or " "
		return c:rep( length - #s ) .. s
	end

	-- Pads string to given length with given char from right.
	function string.rpad( s, length, c )
		s = tostring( s )
		length = length or 2
		c = char or " "
		return s .. c:rep( length - #s )
	end

	-- Splits a string based on the given separator. Returns a table.
	function string.split( s, sep, convert, convertParam )
		if ( type( convert ) ~= "function" ) then
			convert = nil
		end
		if ( type( s ) ~= "string" ) then
			return {}
		end
		sep = sep or " "
		local t = {}
		for token in s:gmatch( "[^" .. sep .. "]+" ) do
			if ( convert ~= nil ) then
				token = convert( token, convertParam )
			end
			table.insert( t, token )
		end
		return t
	end

	-- Formats a string into hex.
	function string.formatToHex( s, sep )
		sep = sep or "-"
		local result = ""
		if ( s ~= nil ) then
			for i = 1, string.len( s ) do
				if ( i > 1 ) then
					result = result .. sep
				end
				result = result .. string.format( "%02X", string.byte( s, i ) )
			end
		end
		return result
	end
end


-- **************************************************
-- Generic utilities
-- **************************************************

function log( msg, methodName, lvl )
	local lvl = lvl or 50
	if ( methodName == nil ) then
		methodName = "UNKNOWN"
	else
		methodName = "(" .. _NAME .. "::" .. tostring( methodName ) .. ")"
	end
	luup.log( string.rpad( methodName, 45 ) .. " " .. tostring( msg ), lvl )
end

local function debug() end

local function warning( msg, methodName )
	log( msg, methodName, 2 )
end

local g_errors = {}
local function error( msg, methodName )
	table.insert( g_errors, { os.time(), tostring( msg ) } )
	if ( #g_errors > 100 ) then
		table.remove( g_errors, 1 )
	end
	log( msg, methodName, 1 )
end


-- **************************************************
-- Variable management
-- **************************************************

Variable = {
	-- Get variable timestamp
	getTimestamp = function( deviceId, variable )
		if ( ( type( variable ) == "table" ) and ( type( variable[4] ) == "string" ) ) then
			local variableTimestamp = VARIABLE[ variable[4] ]
			if ( variableTimestamp ~= nil ) then
				return luup.variable_get( variableTimestamp[1], variableTimestamp[2], deviceId )
			end
		end
		return nil
	end,

	-- Set variable timestamp
	setTimestamp = function( deviceId, variable, timestamp )
		if ( variable[4] ~= nil ) then
			local variableTimestamp = VARIABLE[ variable[4] ]
			if ( variableTimestamp ~= nil ) then
				luup.variable_set( variableTimestamp[1], variableTimestamp[2], ( timestamp or os.time() ), deviceId )
			end
		end
	end,

	-- Get variable value
	get = function( deviceId, variable )
		deviceId = tonumber( deviceId )
		if ( deviceId == nil ) then
			error( "deviceId is nil", "Variable.get" )
			return
		elseif ( variable == nil ) then
			error( "variable is nil", "Variable.get" )
			return
		end
		local value, timestamp = luup.variable_get( variable[1], variable[2], deviceId )
		if ( value ~= "0" ) then
			local storedTimestamp = Variable.getTimestamp( deviceId, variable )
			if ( storedTimestamp ~= nil ) then
				timestamp = storedTimestamp
			end
		end
		return value, timestamp
	end,

	-- Set variable value
	set = function( deviceId, variable, value )
		deviceId = tonumber( deviceId )
		if ( deviceId == nil ) then
			error( "deviceId is nil", "Variable.set" )
			return
		elseif (variable == nil) then
			error( "variable is nil", "Variable.set" )
			return
		elseif (value == nil) then
			error( "value is nil", "Variable.set" )
			return
		end
		if ( type( value ) == "number" ) then
			value = tostring( value )
		end
		local doChange = true
		local currentValue = luup.variable_get( variable[1], variable[2], deviceId )
		local deviceType = luup.devices[deviceId].device_type
		if ( ( currentValue == value ) and ( ( variable[3] == true ) or ( value == "0" ) ) ) then
			-- Variable is not updated when the value is unchanged
			doChange = false
		end

		if doChange then
			luup.variable_set( variable[1], variable[2], value, deviceId )
		end

		-- Updates linked variable for timestamp (just for active value)
		if ( value ~= "0" ) then
			Variable.setTimestamp( deviceId, variable, os.time() )
		end
	end,

	-- Get variable value and init if value is nil or empty
	getOrInit = function( deviceId, variable, defaultValue )
		local value, timestamp = Variable.get( deviceId, variable )
		if ( ( value == nil ) or (  value == "" ) ) then
			Variable.set( deviceId, variable, defaultValue )
			value = defaultValue
			timestamp = os.time()
		end
		return value, timestamp
	end,

	watch = function( deviceId, variable, callback )
		luup.variable_watch( callback, variable[1], variable[2], lul_device )
	end
}


-- **************************************************
-- UI messages
-- **************************************************

UI = {
	show = function( message )
		debug( "Display message: " .. tostring( message ), "UI.show" )
		Variable.set( g_parentDeviceId, VARIABLE.LAST_MESSAGE, message )
	end,

	showError = function( message )
		debug( "Display message: " .. tostring( message ), "UI.showError" )
		message = '<font color="red">' .. tostring( message ) .. '</font>'
		Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, message )
	end,

	clearError = function()
		Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, "" )
	end
}

-- Show Surveillance Station status on UI
function showStatusOnUI()
	local cameraIds = ""
	for _, camera in pairs( g_params.cameras ) do
		cameraIds = cameraIds .. ' <span style="'
		if ((camera.status == 0) or (camera.status == 2)) then
			-- Enabled
			cameraIds = cameraIds .. 'font-weight:bold;'
		elseif ((camera.status == 1) or (camera.status == 3)) then
			-- Disabled
			cameraIds = cameraIds .. 'text-decoration:line-through;'
		else
			-- Problem on camera
			cameraIds = cameraIds .. 'color:red;'
		end
		if (camera.recStatus == 6) then
			cameraIds = cameraIds .. 'color:white;background:red;'
		elseif (camera.recStatus > 0) then
			cameraIds = cameraIds .. 'color:white;background:orange;'
		end
		
		cameraIds = cameraIds .. '">' .. camera.id .. '</span>'
	end
	local message = "<div>"
	message = message .. '<div>SS ' .. tostring(g_params.apiVersion) .. '</div>'
	message = message .. '<div style="color:gray;font-size:.7em;text-align:left;">' ..
							'<div>Camera ids:' .. cameraIds .. '</div> ' ..
							'<div>Licence: ' .. tostring(g_params.quota.iKeyUsed) .. "/" .. tostring(g_params.quota.iKeyTotal) .. '</div>' ..
							'<div>Last update: ' .. os.date('%Y/%m/%d %X', (tonumber(luup.variable_get(SID.SurveillanceStationRemote, "LastUpdate", lul_device) or 0))) .. '</div> ' ..
						'</div>'
	if (g_params.debugMode) then
		message = message .. '<div style="color:gray;font-size:.7em;text-align:left;">Debug enabled</div>'
	end
	message = message .. '</div>'
	UI.show(lul_device, message)
end

local function isDisabled()
	if ( luup.attr_get( "disabled", g_parentDeviceId ) == 1 ) then
		debug( "Device #" .. tostring( g_parentDeviceId ) .. " is disabled", "isDisabled" )
		UI.show( "Device disabled" )
		return true
	end
	return false
end

-- **************************************************
-- Surveillance Station API
-- **************************************************

API = {

	-- Get the url of the method to call
	getUrl = function( apiName, method, version, parameters )
		-- Construct url
		local url = g_params.protocol .. "://" .. g_params.host
		if (g_params.port ~= "") then
			url = url .. ":" .. g_params.port
		end
		url = url .. "/webapi/"
		-- API path
		if (g_params.apiInfo[apiName] ~= nil) then
			url = url .. g_params.apiInfo[apiName].path
		else
			url = url .. "query.cgi"
			if (apiName ~= "SYNO.API.Info") then
				warning( "No info on API '" .. apiName .. "'", "API.getUrl" )
			end
		end
		-- Method and version
		url = url .. "?api=" .. apiName .. "&method=" .. method .. "&version=" .. version
		-- Optionnal parameters
		if ( parameters ~= nil ) then
			for parameterName, value in pairs( parameters ) do
				--url = url .. "&" .. parameterName .. "=" .. Url.escape( tostring( value ) )
				url = url .. "&" .. parameterName .. "=" .. tostring( value )
			end
		end
		return url
	end,

	-- Get data in json response
	getData = function( apiName, response )
		local data, errorCode, errorMessage, isFatalError
		local response = response:gsub( "%[%]","[null]" ) -- Trick for library "json.lua" (UI5)
		local decodeSuccess, jsonResponse = pcall( json.decode, response )
		if not decodeSuccess then
			error( "Response decode error: " .. tostring( jsonResponse ), "API.getData" )
			return nil, nil, "Response decode error", false
		else
			if ( jsonResponse and jsonResponse.success ) then
				data = jsonResponse.data or {}
				debug( "Data: " .. json.encode( data ), "API.getData" )
			else
				errorCode, errorMessage, isFatalError = API.getError( apiName, jsonResponse )
			end
			return data, errorCode, errorMessage, isFatalError
		end
	end,

	-- Get API error
	getError = function( apiName, response )
		if ( ( response == nil ) or ( response.error == nil ) ) then
			return nil
		end
		local errorCode, errorMessage, isFatalError = tonumber( response.error.code ), "Unknown error", false
		if ( errorCode ~= nil ) then
			if ( ( API_ERROR_CODE[ apiName ] ~= nil ) and ( API_ERROR_CODE[ apiName ][ errorCode ] ~= nil ) ) then
				errorMessage = API_ERROR_CODE[ apiName ][ errorCode ][ 1 ]
				isFatalError = API_ERROR_CODE[ apiName ][ errorCode ][ 2 ]
			elseif ( API_ERROR_CODE[ "common" ][ errorCode ] ~= nil ) then
				errorMessage = API_ERROR_CODE[ "common" ][ errorCode ][ 1 ]
				isFatalError = API_ERROR_CODE[ "common" ][ errorCode ][ 2 ]
			end
		end
		return errorCode, errorMessage, isFatalError
	end,

	-- Request Synology API
	request = function( apiName, method, version, parameters, noRetryIfError )
		local url = API.getUrl( apiName, method, version, parameters )
		debug( "Call : " .. url, "API.request" )

		local data = nil
		local nbTry = 1
		local isFatalError = false
		while ( ( data == nil ) and not isFatalError and ( nbTry <= g_params.nbMaxTry ) ) do
			-- Call Synology API
			--local requestBody = {}
			local responseBody = {}
			local b, code, headers = g_params.transporter.request( {
				url = url,
				--source = ltn12.source.string(requestBody),
				headers = {
					cookie = "id=" .. tostring( g_params.sessionId or "" )
				},
				sink = ltn12.sink.table( responseBody )
			} )
			debug( "Response b:" .. tostring( b ) .. " - code: " .. tostring( code ), "API.request" )
			debug( "Response headers:" .. json.encode( headers ), "API.request" )
			if ( ( not b ) or ( code ~= 200 ) ) then
				error( "HTTP error - code:" .. tostring( code ) .. " - response:" .. tostring( response ), "API.request" )
			else
				local response = table.concat( responseBody )
				local contentType = headers[ "content-type" ]
				debug( "ContentType: " .. tostring( contentType ), "API.request" )
				if ( contentType == "image/jpeg" ) then
					local contentLength = tonumber( headers[ "content-length" ] or 0 )
					debug( "Response is an image (" .. tostring( math.ceil( contentLength / 1024 ) ) .. "ko)", "API.request" )
					data = response
				--elseif ( contentType == "application/json" ) then
				else
					--debug( "Response  : " .. tostring( response ), "API.request")
					local errorCode, errorMessage
					data, errorCode, errorMessage, isFatalError = API.getData( apiName, response )
					if ( data == nil ) then
						error( "API error: " .. tostring( errorMessage ) .. " (" .. tostring( errorCode ) .. ")", "API.request" )
						if ( errorCode == 105 ) then
							-- It could be an authentification problem
							-- Try to login
							if API.login() then
								isFatalError = false
							end
						end
					end
				end
			end
			if ( ( data == nil ) and not isFatalError and not noRetryIfError ) then
				nbTry = nbTry + 1
				if ( nbTry <= g_params.nbMaxTry ) then
					luup.sleep( MIN_INTERVAL_BETWEEN_REQUESTS * 1000 )
					debug( "Try #" .. tostring( nbTry ) .. "/" .. tostring( g_params.nbMaxTry ), "API.request" )
				end
			end
		end

		if ( data == nil ) then
			UI.showError( "Error" )
			Variable.set( g_parentDeviceId, VARIABLE.COMM_FAILURE, "1" )
			-- For ALTUI
			luup.attr_set( "status", 2, g_parentDeviceId )
		else
			UI.clearError()
			Variable.set( g_parentDeviceId, VARIABLE.COMM_FAILURE, "0" )
			if ( luup.attr_get( "status", g_parentDeviceId ) == "2" ) then
				-- For ALTUI
				luup.attr_set( "status", -1, g_parentDeviceId )
			end
		end
		return data
	end,

	-- Query APIs’ information (no login required)
	retrieveInfo = function()
		local data = API.request( "SYNO.API.Info", "Query", 1, {
			--query = "SYNO.API.Auth,SYNO.SurveillanceStation.Info,SYNO.SurveillanceStation.Camera,SYNO.SurveillanceStation.ExternalEvent,SYNO.SurveillanceStation.ExternalRecording"
			query = "SYNO.API.Auth,SYNO.SurveillanceStation.Info,SYNO.SurveillanceStation.Camera,SYNO.SurveillanceStation.Camera.Wizard,SYNO.SurveillanceStation.ExternalEvent,SYNO.SurveillanceStation.ExternalRecording"
		})
		if data then
			if ( ( data["SYNO.API.Auth"].maxVersion >= 2 ) and ( data["SYNO.SurveillanceStation.ExternalRecording"].maxVersion >= 2 ) ) then
				g_params.apiInfo = data
				log( "API info retrieved", "API.retrieveInfo" )

				-- Get Surveillance Station version
				data = API.request( "SYNO.SurveillanceStation.Info", "GetInfo", 1, {} )
				if data then
					g_params.apiVersion = tostring( data.version.major ) .. "." .. tostring( data.version.minor ) .. "-" .. tostring( data.version.build )
					log( "Surveillance Station version: " .. g_params.apiVersion, "API.retrieveInfo" )
				else
					error( "Can't retrieve Surveillance Station version", "API.retrieveInfo" )
				end

				return true
			else
				error( "Synology API version is too old - DSM 4.0-2251 and Surveillance Station 6.1 are required", "API.retrieveInfo" )
			end
		else
			error( "Can't connect to Synology host", "API.retrieveInfo" )
		end
		return false
	end,

	-- Session login
	login = function()
		debug( "Try to log in", "API.login" )
		local url = API.getUrl( "SYNO.API.Auth", "Login", 2, {
			account = g_params.userName,
			passwd  = g_params.password,
			session = "SurveillanceStation",
			format  = "cookie"
		} )
		local responseBody = {}
		local b, code, headers = g_params.transporter.request( {
			url = url,
			sink = ltn12.sink.table( responseBody )
		} )
		local response = table.concat( responseBody )
		debug( "Response  : " .. json.encode( response ), "API.request")

		local data, errorCode, errorMessage, isFatalError = API.getData( "SYNO.API.Auth", response )
		if errorCode then
			error( "API error: " .. tostring( errorMessage ) .. " (" .. tostring( errorCode ) .. ")", "API.login" )
			return false
		end
		
		-- Search sessionId in cookie if exist
		local cookie = headers[ "set-cookie" ]
		if ( cookie ) then
			local sessionId = string.match( cookie, "id=([^;,]*)" )
			if sessionId then
				g_params.sessionId = sessionId
				Variable.set( g_parentDeviceId, VARIABLE.SESSION_ID, g_params.sessionId )
				debug( "Session is opened - SID: " .. g_params.sessionId, "API.login" )
				return true
			end
		end

		error( "Login failed", "API.login" )
		return false
	end,

	-- Session logout
	logout = function()
		debug( "Try to log out", "API.logout" )
		local data = API.request( "SYNO.API.Auth", "Logout", 2, { session = "SurveillanceStation" }, false )
		if data then
			Variable.set( g_parentDeviceId, VARIABLE.SESSION_ID, "" )
			g_params.sessionId = nil
			log( "Session is closed", "API.logout" )
			return true
		else
			error( "Logout failed", "API.logout" )
			return false
		end
	end,

	-- Get quota informations
	retrieveQuota = function()
		debug( "Retrieve quota informations", "API.retrieveQuota" )
		local data = API.request( "SYNO.SurveillanceStation.Camera.Wizard", "CheckQuota", 1, {} )
		if data then
			g_params.quota = {
				localCamNum = tonumber( data.localCamNum ) or 0,
				iKeyUsed = tonumber( data.iKeyUsed ) or 0,
				iKeyTotal = tonumber( data.iKeyTotal ) or 0
			}
			if ( ( g_params.quota.iKeyTotal == 0 ) or ( g_params.quota.localCamNum > g_params.quota.iKeyTotal ) ) then
				-- TODO : check if this can detect if the licence has expired
				error( "Problem with licence: " .. tostring( g_params.quota.localCamNum ) .. " installed camera(s) with licence for " .. tostring( g_params.quota.iKeyTotal ), "API.retrieveQuota" )
				UI.showError( "Licence error" )
				return false
			end
			return true
		else
			error( "Can't get quota", "API.retrieveQuota" )
			return false
		end
	end,

	-- Get camera list (require login)
	retrieveCameras = function()
		debug( "Retrieve cameras", "API.retrieveCameras" )
		local data = API.request( "SYNO.SurveillanceStation.Camera", "List", 1, {
			basic = true,
			streamInfo = false
		} )
		if data then
			Cameras.update( data.cameras )
			return true
		else
			error( "Can't get camera list", "API.retrieveCameras" )
			return false
		end
	end,

	-- Get camera snapshot (require login)
	getSnapshot = function( cameraId )
		debug( "Get snapshot from camera #" .. tostring( cameraId ), "API.getSnapshot" )
		local data = API.request( "SYNO.SurveillanceStation.Camera", "GetSnapshot", 4, {
			cameraId = cameraId,
			preview = "true"
		} )
		if data then
			return data
		else
			error( "Can't get snapshot", "API.getSnapshot" )
			return false
		end
	end
}


-- **************************************************
-- Cameras
-- **************************************************

g_cameras = {}

Cameras = {
	update = function( cameras )
		g_cameras = {}
		for _, camera in ipairs( cameras ) do
			local cam = {
				id = camera.id,
				name = camera.name,
				enabled = camera.enabled,
				camStatus = camera.camStatus,
				status = camera.status,
				recStatus = camera.recStatus
			}
			table.insert( g_cameras, cam )
			log( "Camera #" .. tostring( camera.id ) .. " '" .. json.encode( cam ) .. "'", "Cameras.update" )
		end
	end,

	getIds = function()
		local cameraIds = {}
		for _, camera in pairs( g_cameras ) do
			table.insert( cameraIds, camera.id )
		end
		return cameraIds
	end,

	getActiveIds = function()
		local cameraIds = {}
		for _, camera in pairs( g_cameras ) do
			if ( camera.status == 0 ) then
				table.insert( cameraIds, camera.id )
			end
		end
		return cameraIds
	end,

	getRecordingIds = function()
		local cameraIds = {}
		for _, camera in pairs( g_cameras ) do
			if ( camera.recStatus > 0 ) then
				table.insert( cameraIds, camera.id )
			end
		end
		return cameraIds
	end,

	get = function()
		return g_cameras
	end,

	getById = function( cameraId )
		for _, camera in pairs( g_cameras ) do
			if ( tonumber( camera.id ) == tonumber( cameraId ) ) then
				return camera
			end
		end
		error( "Camera #" .. tostring( cameraId ) .. " is unknown", "Cameras.getById" )
		return nil
	end,

	-- Update statuses of Surveillance Station Remote
	updateStatuses = function()
		-- Compute statuses
		local status = "0"
		local recordStatus = "0"
		for _, camera in ipairs( g_cameras ) do
			if ( ( camera.status == 0 ) or ( camera.status == 2 ) ) then
				-- At least one camera is enabled or is about to be enabled
				status = "1"
			end
			if ( camera.recStatus == 6 ) then
				-- At least one camera is external recording
				recordStatus = "1"
			end
		end
		Variable.set( g_parentDeviceId, VARIABLE.SWITCH_POWER, status )
		Variable.set( g_parentDeviceId, VARIABLE.RECORD, recordStatus )
		Variable.set( g_parentDeviceId, VARIABLE.LAST_UPDATE, os.time() )
	end
}


-- **************************************************
-- Poll engine
-- **************************************************

PollEngine = {
	poll = function()
		log( "Start poll", "PollEngine.poll" )

		local pollInterval
		if API.retrieveCameras() then
			Cameras.updateStatuses()
			pollInterval = g_params.pollSettings[ 1 ]
		else
			-- Use the poll interval defined for errors
			pollInterval = g_params.pollSettings[ 2 ]
		end

		debug( "Next poll in " .. tostring( pollInterval ) .. " seconds", "PollEngine.poll" )
		luup.call_delay( "SSR.PollEngine.poll", pollInterval )
	end
}


-- **************************************************
-- HTTP request handler
-- **************************************************

local _handlerCommands = {
	["default"] = function (params, outputFormat)
		return '{"return":"1","msg":"Unknown command \'' .. tostring(params["command"]) .. '\'"}', "application/json"
	end,

	["getInfos"] = function( params, outputFormat )
		-- TODO : info cameras / licences
		--return tostring( json.encode( g_cameras ) ), "application/json"
	end,

	["getCameras"] = function( params, outputFormat )
		return tostring( json.encode( g_cameras ) ), "application/json"
	end,

	-- Get camera snapshot
	["getSnapshot"] = function( params, outputFormat )
		local cameraId = tonumber( params["cameraId"] )
		return getSnapshot( cameraId ), "image/jpeg"
	end,

	["getErrors"] = function( params, outputFormat )
		return tostring( json.encode( g_errors ) ), "application/json"
	end
}
setmetatable( _handlerCommands,{
	__index = function( t, command, outputFormat )
		log( "No handler for command '" ..  tostring( command ) .. "'", "handleHTTPRequest" )
		return _handlerCommands["default"]
	end
})

local function _handleCommand( lul_request, lul_parameters, lul_outputformat )
	local command = lul_parameters["command"] or "default"
	log( "Get handler for command '" .. tostring( command ) .."'", "handleHTTPRequest" )
	return _handlerCommands[ command ]( lul_parameters, lul_outputformat )
end


-- **************************************************
-- Action implementations
-- **************************************************

-- TODO - Disable a camera if out of order
function setOptions( lul_device, lul_settings )
	local options = lul_settings.newOptions or "{}"
	local decodeSuccess, jsonOptions = pcall( json.decode, options )
	if ( not decodeSuccess ) then
		UI.showError( "Options decode error: " .. tostring(jsonOptions) )
		debug( "Options: " .. tostring(options), "setOptions" )
	else

	end
end

-- Update Surveillance Station informations
function update (lul_device, lul_settings)
	debug( "Update", "update" )
	API.logout() -- Force session cookie generation
	if API.retrieveCameras() then
		Cameras.updateStatuses()
	end
end

-- Enable or disable cameras (list or all)
function setTarget( lul_device, lul_settings )
	local method, cameraIdList

	if isDisabled() then
		return
	end

	-- Method name
	if ( ( lul_settings.newTargetValue ~= nil ) and ( tostring( lul_settings.newTargetValue ) == "0" ) ) then
		method = "Disable"
	else
		method = "Enable"
	end
	-- Get camera ids list or compute it
	cameraIdList = lul_settings.cameraIds or lul_settings.cameraId or table.concat( Cameras.getIds(), "," )

	debug( method .. " camera(s) #" .. tostring( cameraIdList ), "setTarget" )
	UI.show( method .. " camera(s) #" .. tostring(cameraIdList) .. "..." )
	local data = API.request( "SYNO.SurveillanceStation.Camera", method, 3, {
		cameraIds = tostring( cameraIdList )
	} )
	if data then
		-- Update the status of the cameras
		if ( type( data.data.camera ) == "table" ) then
			for _, dataCamera in pairs( data.data.camera ) do
				local camera = Cameras.getById( dataCamera.id )
				if camera then
					if dataCamera.enabled then
						camera.status = 0
					else
						camera.status = 1
					end
				end
			end
		end
		--API.retrieveCameras()
		Cameras.updateStatuses()
	else
		error( "Can not " .. method .. " camera(s) #" .. tostring( cameraIdList ), "setTarget" )
		UI.showError( method .. " error" )
	end
end

-- Start or stop external record on one camera
function setRecordTarget( lul_device, lul_settings )
	local deviceStatus, action
	local cameraIds

	if isDisabled() then
		return
	end
	if ( Variable.get( lul_device, VARIABLE.SWITCH_POWER ) ~= "1" ) then
		debug( "Device is switched off", "setRecordTarget" )
		UI.show( "Device disabled" )
		return
	end

	-- Action name
	if ( tostring( lul_settings.newRecordTargetValue ) == "1" ) then
		action = "start"
	else
		action = "stop"
	end
	-- Camera ids
	if ( lul_settings.cameraId ~= nil ) then
		--cameraIds = { [[lul_settings.cameraId]] }
		local cameraId = lul_settings.cameraId
		cameraIds = { cameraId }
	else
		cameraIds = Cameras.getIds()
	end

	debug( action .. " record for camera(s) #" .. tostring( table.concat( cameraIds, "," ) ) .. "...", "setRecordTarget" )

	local result = true
	for _, cameraId in pairs( cameraIds ) do
		local camera = Cameras.getById( cameraId )
		if camera then
			debug( action .. " record for camera #" .. tostring(cameraId), "setRecordTarget" )
			local data = API.request( "SYNO.SurveillanceStation.ExternalRecording", "Record", 2, {
				cameraId = cameraId,
				action = action
			})
			if data then
				if ( action == "start" ) then
					camera.recStatus = 6
				else
					camera.recStatus = 0
				end
			else
				error( "Can not " .. action .. " record for camera #" .. tostring(cameraId), "setRecordTarget" )
				result = false
				break
			end
		end
	end
	if result then
		if ( table.getn( Cameras.getRecordingIds() ) > 0 ) then
			Variable.set( lul_device, VARIABLE.RECORD, "1" )
		else
			Variable.set( lul_device, VARIABLE.RECORD, "0" )
		end
	else
		UI.showError( "Record error" )
	end
end

-- Trigger external event
function triggerExternalEvent( lul_device, lul_settings )
	if isDisabled() then
		return
	end

	local eventId = tonumber( lul_settings.eventId ) or 0
	if ( ( eventId < 1 ) or ( eventId > 10 ) ) then
		error( "Event id '" .. tostring( lul_settings.eventId ) .. "' is not in (1-10)", "triggerExternalEvent" )
		UI.showError( "Input error" )
		return
	end

	debug( "Trigger event #" .. tostring( eventId ), "triggerExternalEvent" )
	UI.show( "Trigger event #" .. tostring(eventId) .. "..." )
	local data = API.request( "SYNO.SurveillanceStation.ExternalEvent", "Trigger", 1, {
		eventId = eventId
	} )
	if data then
		UI.show( "Event #" .. tostring(eventId) .. " sent" )
	else
		error( "Event #" .. tostring(eventId) .. " has not been triggered", "triggerExternalEvent" )
		UI.showError( "Event error" )
	end

end

-- Get a snapshot
function getSnapshot( cameraId )
	if isDisabled() then
		return
	end

	if ( cameraId == nil ) then
		cameraId = Cameras.getActiveIds()[ 1 ]
	end
	local camera = Cameras.getById( cameraId )
	if ( not camera or not camera.enabled ) then
		log( "Camera #" .. tostring(cameraId) .. " is not enabled", "getSnapshot" )
		-- TODO : return image for disabled
		return
	end
	debug( "Get Snapshot for camera #" .. tostring(cameraId), "getSnapshot" )
	local snapshot = API.getSnapshot( cameraId )
	if ( snapshot == nil ) then
		error( "Can not get snapshot for camera #" .. tostring(cameraId), "getSnapshot" )
		UI.showError( "Snapshot error" )
	end
	return snapshot
end


-- **************************************************
-- Startup
-- **************************************************

-- Init plugin instance
-- In case if user/password has changed
local function _initPluginInstance2()
	API.logout()
	_initPluginInstance()
end

-- Init plugin instance
local function _initPluginInstance()
	log( "Init", "initPluginInstance" )

	-- Update the Debug Mode
	local debugMode = ( Variable.getOrInit( g_parentDeviceId, VARIABLE.DEBUG_MODE, "0" ) == "1" ) and true or false
	if debugMode then
		log( "DebugMode is enabled", "init" )
		debug = log
	else
		log( "DebugMode is disabled", "init" )
		debug = function() end
	end

	local isInitialized = true

	Variable.set( g_parentDeviceId, VARIABLE.PLUGIN_VERSION, _VERSION )
	Variable.set( g_parentDeviceId, VARIABLE.LAST_MESSAGE, "" )
	Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, "" )
	Variable.getOrInit( g_parentDeviceId, VARIABLE.SWITCH_POWER, "0" )
	Variable.getOrInit( g_parentDeviceId, VARIABLE.RECORD, "0" )
	Variable.getOrInit( g_parentDeviceId, VARIABLE.COMM_FAILURE, "0" )
	Variable.getOrInit( g_parentDeviceId, VARIABLE.COMM_FAILURE_TIME, "0" )
	Variable.getOrInit( g_parentDeviceId, VARIABLE.LAST_UPDATE, "0" )
	-- Get plugin params
	g_params = {
		apiInfo        = {},
		apiVersion     = "",
		protocol       = Variable.getOrInit( g_parentDeviceId, VARIABLE.PROTOCOL, "http" ),
		host           = Variable.getOrInit( g_parentDeviceId, VARIABLE.HOST, "diskstation" ),
		port           = Variable.getOrInit( g_parentDeviceId, VARIABLE.PORT, "5000" ),
		userName       = Variable.getOrInit( g_parentDeviceId, VARIABLE.USERNAME, "" ),
		password       = Variable.getOrInit( g_parentDeviceId, VARIABLE.PASSWORD, "" ),
		sessionId      = Variable.getOrInit( g_parentDeviceId, VARIABLE.SESSION_ID, "" ),
		nbMaxTry     = tonumber( ( Variable.getOrInit( g_parentDeviceId, VARIABLE.NB_MAX_TRY, NB_MAX_TRY ) ) ) or NB_MAX_TRY,
		requestTimeout = tonumber( ( Variable.getOrInit( g_parentDeviceId, VARIABLE.REQUEST_TIMEOUT, REQUEST_TIMEOUT ) ) ) or REQUEST_TIMEOUT,
		pollSettings = string.split( Variable.getOrInit( g_parentDeviceId, VARIABLE.POLL_SETTINGS, "30,700,700" ), ",", tonumber )
	}

	if ( ( g_params.pollSettings[ 1 ] or 0 ) < MIN_POLL_INTERVAL ) then
		g_params.pollSettings[ 1 ] = MIN_POLL_INTERVAL
	end
	if ( ( g_params.pollSettings[ 2 ] or 0 ) < MIN_POLL_INTERVAL_AFTER_ERROR ) then
		g_params.pollSettings[ 2 ] = MIN_POLL_INTERVAL_AFTER_ERROR
	end

	-- Choose transporter
	if ( g_params.protocol == "https" ) then
		g_params.transporter = require( "ssl.https" )
	else
		g_params.transporter = require( "socket.http" )
	end

	-- Check settings
	if ( g_params.userName == "" ) then
		error( "Variable 'UserName' must be set", "initPluginInstance" )
		UI.showError( "Setting error" )
	elseif ( g_params.password == "" ) then
		error( "Variable 'Password' must be set", "initPluginInstance" )
		UI.showError( "Setting error" )
	-- Try to get API infos
	elseif (
		not API.retrieveInfo()
		or not API.retrieveQuota()
		or not API.retrieveCameras()
	) then
		isInitialized = false
	end
	Cameras.updateStatuses()

	return isInitialized
end

function startup( lul_device )
	log( "Start plugin '" .. _NAME .. "' (v" .. _VERSION .. ")", "startup" )

	-- Get the master device
	g_parentDeviceId = lul_device

	-- Check if the device is disabled
	if isDisabled() then
		return false, "Device #" .. tostring( g_parentDeviceId ) .. " is disabled"
	end

	-- Check if JSON library is available
	if ( type(json) == "string" ) then
		error( "No JSON decoder", "startup" )
		UI.showError( "No JSON decoder" )
		return false, "No JSON decoder"
	end

	-- Update static JSON file
	if updateStaticJSONFile( g_parentDeviceId, _NAME .. "1" ) then
		warning("startup", "'device_json' has been updated : reload LUUP engine")
		luup.reload()
		return false, "Reload LUUP engine"
	end

	-- Init and start poll engine
	if _initPluginInstance() then
		luup.call_delay( "SSR.PollEngine.poll", MIN_POLL_INTERVAL )
	else
		luup.call_delay( "SSR.PollEngine.poll", MIN_POLL_INTERVAL_AFTER_ERROR )
	end

	-- Watch setting changes
	Variable.watch( g_parentDeviceId, VARIABLE.PROTOCOL, "SSR.initPluginInstance" )
	Variable.watch( g_parentDeviceId, VARIABLE.HOST, "SSR.initPluginInstance" )
	Variable.watch( g_parentDeviceId, VARIABLE.PORT, "SSR.initPluginInstance" )
	Variable.watch( g_parentDeviceId, VARIABLE.USERNAME, "SSR.initPluginInstance2" )
	Variable.watch( g_parentDeviceId, VARIABLE.PASSWORD, "SSR.initPluginInstance2" )
	Variable.watch( g_parentDeviceId, VARIABLE.PROTOCOL, "SSR.initPluginInstance" )
	Variable.watch( g_parentDeviceId, VARIABLE.DEBUG_MODE, "SSR.initPluginInstance" )
	Variable.watch( g_parentDeviceId, VARIABLE.POLL_SETTINGS, "SSR.initPluginInstance" )

	-- Request handler
	luup.register_handler( "SSR.handleCommand", "SurveillanceStationRemote_" .. tostring( g_parentDeviceId ) )

	if ( luup.version_major >= 7 ) then
		luup.set_failure( 0, g_parentDeviceId )
	end

	return true
end


-- Promote the functions used by Vera's luup.xxx functions to the global name space
_G["SSR.initPluginInstance"] = _initPluginInstance
_G["SSR.initPluginInstance2"] = _initPluginInstance2
_G["SSR.handleCommand"] = _handleCommand
_G["SSR.PollEngine.poll"] = PollEngine.poll
