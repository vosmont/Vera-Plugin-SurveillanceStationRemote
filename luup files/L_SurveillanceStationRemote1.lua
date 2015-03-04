-- Imports
local json = require("dkjson")
if (type(json) == "string") then
	json = require("json")
end
local http = require("socket.http")

-- Plugin constants
local SID_SurveillanceStationRemote = "urn:upnp-org:serviceId:SurveillanceStationRemote1"
local SID_SecuritySensor = "urn:micasaverde-com:serviceId:SecuritySensor1"

-- Synology API Error Code
local API_ERROR_CODE = {
	["common"] = {
		[100] = "Unknown error",
		[101] = "Invalid parameters",
		[102] = "API does not exist",
		[103] = "Method does not exist",
		[104] = "This API version is not supported",
		[105] = "Insufficient user privilege",
		[106] = "Connection time out",
		[107] = "Multiple login detected"
	},
	["SYNO.API.Auth"] = {
		[100] = "Unknown error",
		[101] = "The account parameter is not specified",
		[400] = "Invalid password",
		[401] = "Guest or disabled account",
		[402] = "Permission denied",
		[403] = "One time password not specified",
		[404] = "One time password authenticate failed"
	},
	["SYNO.SurveillanceStation.Camera"] = {
		[400] = "Execution failed",
		[401] = "Parameter invalid",
		[402] = "Camera disabled"
	},
	["SYNO.SurveillanceStation.PTZ"] = {
		[400] = "Execution failed",
		[401] = "Parameter invalid",
		[402] = "Camera disabled"
	},
	["SYNO.SurveillanceStation.ExternalRecording"] = {
		[400] = "Execution failed",
		[401] = "Parameter invalid",
		[402] = "Camera disabled"
	}
}

-------------------------------------------
-- Plugin variables
-------------------------------------------

local PLUGIN_NAME = "SurveillanceStationRemote"
local PLUGIN_VERSION = "0.7"
local REQUEST_TIMEOUT = 10
local pluginsParam = {}

-------------------------------------------
-- UI compatibility
-------------------------------------------

-- Update static JSON file
local function updateStaticJSONFile (pluginName)
	local isUpdated = false
	if (luup.version_branch ~= 1) then
		luup.log("ERROR - Plugin '" .. pluginName .. "' - checkStaticJSONFile : don't know how to do with this version branch " .. tostring(luup.version_branch), 1)
	elseif (luup.version_major > 5) then
		local currentStaticJsonFile = luup.attr_get("device_json", lul_device)
		local expectedStaticJsonFile = "D_" .. pluginName .. "_UI" .. tostring(luup.version_major) .. ".json"
		if (currentStaticJsonFile ~= expectedStaticJsonFile) then
			luup.attr_set("device_json", expectedStaticJsonFile, lul_device)
			isUpdated = true
		end
	end
	return isUpdated
end

-------------------------------------------
-- Tool functions
-------------------------------------------

-- Get variable value and init if value is nil
function getVariableOrInit (lul_device, serviceId, variableName, defaultValue)
	local value = luup.variable_get(serviceId, variableName, lul_device)
	if (value == nil) then
		luup.variable_set(serviceId, variableName, defaultValue, lul_device)
		value = defaultValue
	end
	return value
end

local function log(methodName, text, level)
	luup.log("(" .. PLUGIN_NAME .. "::" .. tostring(methodName) .. ") " .. tostring(text), (level or 50))
end

local function error(methodName, text)
	log(methodName, "ERROR: " .. tostring(text), 1)
end

local function warning(methodName, text)
	log(methodName, "WARNING: " .. tostring(text), 2)
end

local function debug(methodName, text)
	if (pluginParams.debug) then
		log(methodName, "DEBUG: " .. tostring(text))
	end
end

-------------------------------------------
-- Plugin functions
-------------------------------------------

local function setMessage (lul_device, message)
	luup.variable_set(SID_SurveillanceStationRemote, "LastError", tostring(message), lul_device)
end
--
local function setLastError (lul_device, lastError)
	if (pluginParams.lastError ~= "") then
		pluginParams.lastError = pluginParams.lastError .. " / " .. tostring(lastError)
	else
		pluginParams.lastError = tostring(lastError)
	end
	error("setLastError", pluginParams.lastError)
	luup.variable_set(SID_SurveillanceStationRemote, "LastError", pluginParams.lastError, lul_device)
end

-- Request Synology API
local function requestAPI (lul_device, apiName, method, version, parameters)
	-- Construct url
	local url = pluginParams.protocol .. "://" .. pluginParams.host
	if (pluginParams.port ~= "") then
		url = url .. ":" .. pluginParams.port
	end
	url = url .. "/webapi/"
	-- API path
	if (pluginParams.apiInfo[apiName] ~= nil) then
		url = url .. pluginParams.apiInfo[apiName].path
	else
		url = url .. "query.cgi"
		if (apiName ~= "SYNO.API.Info") then
			warning("requestAPI", "No info on API '" .. apiName .. "'")
		end
	end
	-- Method and version
	url = url .. "?api=" .. apiName .. "&method=" .. method .. "&version=" .. version
	-- Add session id if defined
	if (pluginParams.sessionId ~= nil) then
		url = url .. "&_sid=" .. pluginParams.sessionId
	end
	-- Optionnal parameters
	if (parameters ~= nil) then
		for parameterName, value in pairs(parameters) do
			url = url .. "&" .. parameterName .. "=" .. tostring(value)
		end
	end

	debug("requestAPI", "Call : " .. url)

	-- Call Synology API
	local data = {}
	local status, response = luup.inet.wget(url, REQUEST_TIMEOUT)
	--local response, status = http.request(url)
	debug("requestAPI", "Response status : " .. tostring(status))
	if (status ~= 0) then
	--if (response == nil) then
		-- HTTP error
		setLastError(lul_device, "HTTP error: " .. tostring(status))
	else
		response = response:gsub("%[%]","[null]")
		local decodeSuccess, jsonResponse = pcall(json.decode, response)
		if (not decodeSuccess) then
			setLastError(lul_device, "Response decode error: " .. tostring(jsonResponse))
			debug("requestAPI", "Response: " .. tostring(response))
		else
			if (jsonResponse.success) then
				status = 0
				data = jsonResponse.data
				--debug("requestAPI", "Data: " .. json.encode(data))
			else
				-- API error
				status = -1
				local errorCode, errorMessage = tonumber(jsonResponse.error.code), "unkown"
				if ((API_ERROR_CODE[apiName] ~= nil) and (API_ERROR_CODE[apiName][errorCode] ~= nil)) then
					errorMessage = API_ERROR_CODE[apiName][errorCode]
				elseif (API_ERROR_CODE["common"][errorCode] ~= nil) then
					errorMessage = API_ERROR_CODE["common"][errorCode]
				end
				setLastError(lul_device, "API error: "  .. tostring(errorMessage) .. " (" .. tostring(errorCode) .. ")")
			end
		end
	end

	return status, data
end

-- Query APIs’ information (no login required)
local function retrieveApiInfo (lul_device)
	local status, data = requestAPI(lul_device, "SYNO.API.Info", "Query", 1, {
		query = "SYNO.API.Auth,SYNO.SurveillanceStation.Info,SYNO.SurveillanceStation.Camera,SYNO.SurveillanceStation.ExternalRecording"
	})
	if (status == 0) then
		if ((data["SYNO.API.Auth"].maxVersion >= 2) and (data["SYNO.SurveillanceStation.ExternalRecording"].maxVersion >= 2)) then
			pluginParams.apiInfo = data
			log("retrieveApiInfo", "API info retrieved")

			-- Get Surveillance Station version
			status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.Info", "GetInfo", 1, {})
			if (status == 0) then
				pluginParams.apiVersion = tostring(data.version.major) .. "." .. tostring(data.version.minor) .. "-" .. tostring(data.version.build)
				log("retrieveApiInfo", "Surveillance Station version: " .. pluginParams.apiVersion)
				--luup.variable_set(SID_SurveillanceStationRemote, "LastError", "SS: " .. pluginParams.apiVersion, lul_device)
			else
				setLastError(lul_device, "Can't retrieve Surveillance Station version")
			end

			return true
		else
			setLastError(lul_device, "Synology API version is too old - DSM 4.0-2251 and Surveillance Station 6.1 are required")
		end
	else
		setLastError(lul_device, "Can't connect to Synology host")
	end
	return false
end

-- Session login
local function login (lul_device)
	pluginParams.sessionId = nil
	local status, data = requestAPI(lul_device, "SYNO.API.Auth", "Login", 2, {
		account = pluginParams.userName,
		passwd  = pluginParams.password,
		session = "SurveillanceStation",
		format  = "sid"
	})
	if ((status == 0) and (data.sid ~= nil)) then
		pluginParams.sessionId = data.sid
		log("login", "Session is opened - SID : " .. pluginParams.sessionId)
		luup.sleep(1000)
		return true
	else
		setLastError(lul_device, "Login failed")
		return false
	end
end

-- Session logout
local function logout (lul_device)
	local status, data = requestAPI(lul_device, "SYNO.API.Auth", "Logout", 2, { session = "SurveillanceStation" })
	if (status == 0) then
		pluginParams.sessionId = nil
		log("logout", "Session is closed")
		return true
	else
		setLastError(lul_device, "Logout failed")
		return false
	end
end

-- Get camera list (require login)
local function retrieveCameras (lul_device)
	local status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.Camera", "List", 2, {
		limit = 10,
		additional = "device"
	})
	if (status == 0) then
		pluginParams.cameras = data.cameras
		-- Save camera list
		local cameraList = {}
		for _, camera in ipairs(pluginParams.cameras) do
			log("retrieveCameras", "Get camera #" .. tostring(camera.id) .. " '" .. camera.name .. "'")
			table.insert(cameraList, tostring(camera.id) .. "," .. tostring(camera.name) .. "," .. tostring(camera.status) .. "," .. tostring(camera.recStatus))
		end
		luup.variable_set(SID_SurveillanceStationRemote, "Cameras", table.concat(cameraList, "|"), lul_device)
		return true
	else
		setLastError(lul_device, "Can't get camera list")
		return false
	end
end

local function updateStatuses (lul_device)
	if (retrieveCameras(lul_device)) then
		-- Compute statuses
		local armedStatus = "1"
		local recordStatus = "0"
		for _, camera in pairs(pluginParams.cameras) do
			if (tonumber(camera.status) > 0) then
				-- At least one camera is disable
				armedStatus = "0"
			elseif ((armedStatus == "1") and (tonumber(camera.recStatus) == 6)) then
				-- Device not disable ant at least one camera is recording
				recordStatus = "1"
			end
		end
		luup.variable_set(SID_SecuritySensor, "Armed", armedStatus, lul_device)
		luup.variable_set(SID_SurveillanceStationRemote, "Record", recordStatus, lul_device)
		return true
	else
		return false
	end
end

local function getCameraIds (lul_device)
	local cameraIds = {}
	for _, camera in pairs(pluginParams.cameras) do
		table.insert(cameraIds, camera.id)
	end
	return cameraIds
end

local function getCameraById (lul_device, cameraId)
	for _, camera in pairs(pluginParams.cameras) do
		if (tonumber(camera.id) == tonumber(cameraId)) then
			return camera
		end
	end
	error("getCameraById", "Camera #" .. tostring(cameraId) .. " is unknown")
	return nil
end

-- Change debug level log
function onDebugValueIsUpdated (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	if (lul_value_new == "1") then
		log("onDebugValueIsUpdated", "Enable debug mode")
		pluginParams.debug = true
	else
		log("onDebugValueIsUpdated", "Disable debug mode")
		pluginParams.debug = false
	end
end

-------------------------------------------
-- Job functions
-------------------------------------------

function update (lul_device, lul_settings, lul_job)
	debug("update", "Update")
	setMessage(lul_device, "Update...")
	pluginParams.lastError = ""

	if (pluginParams.isBusy) then
		warning("setArmed", "Last call is still in process")
	else
		pluginParams.isBusy = true
	end

	if (login(lul_device)) then
		updateStatuses(lul_device)
		logout(lul_device)
	end

	if (pluginParams.lastError == "") then
		luup.variable_set(SID_SurveillanceStationRemote, "LastError", "SS: " .. pluginParams.apiVersion, lul_device)
	end

	pluginParams.isBusy = false
	return 4, nil
end

-- Enable or disable cameras (list or all)
function setArmed (lul_device, lul_settings, lul_job)
	local method, cameraIdList

	if (pluginParams.isBusy) then
		setMessage(lul_device, "Last call is still in process...")
	else
		pluginParams.isBusy = true
	end

	-- Method name
	if ((lul_settings.newArmedValue ~= nil) and (tostring(lul_settings.newArmedValue) == "0")) then
		method = "Disable"
	else
		method = "Enable"
	end
	-- Get camera ids list or compute it
	cameraIdList = lul_settings.cameraIds or lul_settings.cameraId or table.concat(getCameraIds(lul_device), ",")

	debug("setTarget", method .. " camera(s) #" .. tostring(cameraIdList))
	setMessage(lul_device, method .. " camera(s) #" .. tostring(cameraIdList) .. "...")
	pluginParams.lastError = ""
	if (login(lul_device)) then
		local status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.Camera", method, 3, {
			cameraIds = tostring(cameraIdList)
		})
		if (status == 0) then
			updateStatuses(lul_device)
		end
		logout(lul_device)
	end

	if (pluginParams.lastError == "") then
		setMessage(lul_device, "SS: " .. pluginParams.apiVersion)
	end

	pluginParams.isBusy = false
	return 4, nil
end

-- Start or stop external record on one camera
function setRecordTarget (lul_device, lul_settings)
	local result = false
	local deviceStatus, action
	local cameraIds

	if (pluginParams.isBusy) then
		warning("setArmed", "Last call is still in process")
	else
		pluginParams.isBusy = true
	end

	if (luup.variable_get(SID_SecuritySensor, "Armed", lul_device) ~= "1") then
		debug("setRecordTarget", "Device is disable : do nothing")
	else
		-- Action name
		if (tostring(lul_settings.newRecordTargetValue) == "1") then
			action = "start"
			recordStatus = "1"
		else
			action = "stop"
			recordStatus = "0"
		end
		-- Camera ids
		if (lul_settings.cameraId ~= nil) then
			--cameraIds = { [[lul_settings.cameraId]] }
			local cameraId = lul_settings.cameraId
			cameraIds = { cameraId }
		else
			cameraIds = getCameraIds(lul_device)
		end

		setMessage(lul_device, action .. " record for camera(s) #" .. tostring(table.concat(cameraIds, ",")) .. "...")
		pluginParams.lastError = ""

		if (login(lul_device)) then
			for _, cameraId in pairs(cameraIds) do
				debug("setRecordTarget", action .. " record for camera #" .. tostring(cameraId))
				local status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.ExternalRecording", "Record", 2, {
					cameraId = cameraId,
					action = action
				})
				if (status == 0) then
					result = true
				end
			end
			if (result) then
				luup.variable_set(SID_SurveillanceStationRemote, "Record", recordStatus, lul_device)
			end
			--updateStatuses(lul_device)) then
			logout(lul_device)
		end

		if (pluginParams.lastError == "") then
			setMessage(lul_device, "SS: " .. pluginParams.apiVersion)
		end
	end

	pluginParams.isBusy = false
	return 4, nil
end

-------------------------------------------
-- Startup
-------------------------------------------

-- Init plugin instance
function initPluginInstance (lul_device)
	log("initPluginInstance", "Init")

	local isInitialized = true
	setMessage(lul_device, "Init plugin instance...")

	-- Get plugin params for this device
	getVariableOrInit(lul_device, SID_SecuritySensor, "Armed", "0")
	getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "Record", "0")
	getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "LastError", "")
	pluginParams = {
		deviceName = "SurveillanceStationRemote(" .. tostring(lul_device) .. ")",
		apiInfo    = {},
		apiVersion = "",
		protocol   = getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "Protocol", "http"),
		host       = getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "Host", "diskstation"),
		port       = getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "Port", "5000"),
		userName   = getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "UserName", ""),
		password   = getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "Password", ""),
		cameras    = getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "Cameras", ""),
		lastError  = "",
		debug      = (getVariableOrInit(lul_device, SID_SurveillanceStationRemote, "Debug", "0") == "1"),
		isBusy     = false
	}

	-- Check param
	if ((pluginParams.userName == "") or (pluginParams.password == "")) then
		setLastError(lul_device, "Variables 'UserName' and 'Password' must be set")
		isInitialized = false
	-- Try to get API infos
	elseif (not retrieveApiInfo(lul_device)) then
		setLastError(lul_device, "API Info KO")
		isInitialized = false
	-- Try to log in
	elseif (not login(lul_device)) then
		setLastError(lul_device, "Login KO")
		isInitialized = false
	-- Try to update infos
	elseif (not updateStatuses(lul_device)) then
		setLastError(lul_device, "Update KO")
		isInitialized = false
	end

	-- Log out
	logout(lul_device)

	if (pluginParams.lastError == "") then
		setMessage(lul_device, "SS: " .. pluginParams.apiVersion)
	end

	return isInitialized
end

function startup (lul_device)
	log("startup", "Start plugin '" .. PLUGIN_NAME .. "' (v" .. PLUGIN_VERSION .. ")")

	if (type(json) == "string") then
		setMessage(lul_device, "No JSON decoder")
		return false, "No JSON decoder"
	end

	-- Update static JSON file
	if updateStaticJSONFile(PLUGIN_NAME .. "1") then
		warning("startup", "'device_json' has been updated : reload LUUP engine")
		luup.reload()
		return false, "Reload LUUP engine"
	end

	-- Init
	initPluginInstance(lul_device)

	-- Register
	luup.variable_watch("initPluginInstance", SID_SurveillanceStationRemote, "Protocol", lul_device)
	luup.variable_watch("initPluginInstance", SID_SurveillanceStationRemote, "Host", lul_device)
	luup.variable_watch("initPluginInstance", SID_SurveillanceStationRemote, "Port", lul_device)
	luup.variable_watch("initPluginInstance", SID_SurveillanceStationRemote, "UserName", lul_device)
	luup.variable_watch("initPluginInstance", SID_SurveillanceStationRemote, "Password", lul_device)
	luup.variable_watch("onDebugValueIsUpdated", SID_SurveillanceStationRemote, "Debug", lul_device)

	if (luup.version_major >= 7) then
		luup.set_failure(0, lul_device)
	end

	return true
end
