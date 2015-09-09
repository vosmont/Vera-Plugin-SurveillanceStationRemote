-- Imports
local json = require("dkjson")
if (type(json) == "string") then
	json = require("json")
end

local http = require("socket.http")
local ltn12 = require("ltn12")

-------------------------------------------
-- Constants
-------------------------------------------

local SID = {
	SurveillanceStationRemote = "urn:upnp-org:serviceId:SurveillanceStationRemote1",
	SwitchPower = "urn:upnp-org:serviceId:SwitchPower1",
	HaDevice = "urn:micasaverde-com:serviceId:HaDevice1"
}

-- Synology API Error Code
local API_ERROR_CODE = {
	["common"] = {
		[100] = {"Unknown error", false},
		[101] = {"Invalid parameters", false},
		[102] = {"API does not exist", true},
		[103] = {"Method does not exist", true},
		[104] = {"This API version is not supported", true},
		[105] = {"Insufficient user privilege", false}, -- test
		[106] = {"Connection time out", false},
		[107] = {"Multiple login detected", false}
	},
	["SYNO.API.Auth"] = {
		[100] = {"Unknown error", false},
		[101] = {"The account parameter is not specified", true},
		[400] = {"Invalid password", true},
		[401] = {"Guest or disabled account", true},
		[402] = {"Permission denied", false},
		[403] = {"One time password not specified", true},
		[404] = {"One time password authenticate failed", true}
	},
	["SYNO.SurveillanceStation.Camera"] = {
		[400] = {"Execution failed", false},
		[401] = {"Parameter invalid", false},
		[402] = {"Camera disabled", false},
		[407] = {"CMS closed", false}
	},
	["SYNO.SurveillanceStation.ExternalEvent"] = {
		-- ???
	},
	["SYNO.SurveillanceStation.ExternalRecording"] = {
		[400] = {"Execution failed", false},
		[401] = {"Parameter invalid", false},
		[402] = {"Camera disabled", false}
	},
	["SYNO.SurveillanceStation.PTZ"] = {
		[400] = {"Execution failed", false},
		[401] = {"Parameter invalid", false},
		[402] = {"Camera disabled", false}
	}
}

-------------------------------------------
-- Plugin constants
-------------------------------------------

local PLUGIN_NAME = "SurveillanceStationRemote"
local PLUGIN_VERSION = "0.61"
local REQUEST_TIMEOUT = 10
local NB_MAX_RETRY = 2
local PING_INTERVAL = 60

-------------------------------------------
-- Plugin variables
-------------------------------------------

local pluginParams = {}

-------------------------------------------
-- UI compatibility
-------------------------------------------

-- Update static JSON file
function updateStaticJSONFile (lul_device, pluginName)
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

-- Set variable value if modified
function setVariable (lul_device, serviceId, variableName, value)
	local formerValue = luup.variable_get(serviceId, variableName, lul_device)
	if (value ~= formerValue) then
		luup.variable_set(serviceId, variableName, value, lul_device)
	end
end

function log(methodName, text, level)
	luup.log("(" .. PLUGIN_NAME .. "::" .. tostring(methodName) .. ") " .. tostring(text), (level or 50))
end

function error(methodName, text)
	log(methodName, "ERROR: " .. tostring(text), 1)
end

function warning(methodName, text)
	log(methodName, "WARNING: " .. tostring(text), 2)
end

function debug(methodName, text)
	if (pluginParams.debugMode) then
		log(methodName, "DEBUG: " .. tostring(text))
	end
end

-- Change debug level log
function onDebugValueIsUpdated (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	if (tonumber(lul_value_new) > 0) then
		log("onDebugValueIsUpdated", "Enable debug mode")
		pluginParams.debugMode = true
	else
		log("onDebugValueIsUpdated", "Disable debug mode")
		pluginParams.debugMode = false
	end
end

-------------------------------------------
-- Display on UI functions
-------------------------------------------

-- Show message on UI
function showMessageOnUI (lul_device, message)
	setVariable(lul_device, SID.SurveillanceStationRemote, "Message", tostring(message))
end

-- Show error on UI (and add to previous error)
function showErrorOnUI (methodName, lul_device, message, hasToSave)
	if (pluginParams.lastError ~= "") then
		pluginParams.lastError = pluginParams.lastError .. " / " .. tostring(message)
	else
		pluginParams.lastError = tostring(message)
	end
	error(methodName, pluginParams.lastError)
	showMessageOnUI(lul_device, "<font color=\"red\">" .. tostring(pluginParams.lastError) .. "</font>")
	if hasToSave then
		setVariable(lul_device, SID.SurveillanceStationRemote, "LastError", tostring(message))
	end
end

-- Show Surveillance Station status on UI
function showStatusOnUI (lul_device)
	local cameraIds = ""
	for _, camera in pairs(pluginParams.cameras) do
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
	message = message .. '<div>SS ' .. tostring(pluginParams.apiVersion) .. '</div>'
	message = message .. '<div style="color:gray;font-size:.7em;text-align:left;">' ..
							'<div>Camera ids:' .. cameraIds .. '</div> ' ..
							'<div>Licence: ' .. tostring(pluginParams.quota.iKeyUsed) .. "/" .. tostring(pluginParams.quota.iKeyTotal) .. '</div>' ..
							'<div>Last update: ' .. os.date('%Y/%m/%d %X', (tonumber(luup.variable_get(SID.SurveillanceStationRemote, "LastUpdate", lul_device) or 0))) .. '</div> ' ..
						'</div>'
	if (pluginParams.debugMode) then
		message = message .. '<div style="color:gray;font-size:.7em;text-align:left;">Debug enabled</div>'
	end
	message = message .. '</div>'
	showMessageOnUI(lul_device, message)
end

-------------------------------------------
-- Plugin functions
-------------------------------------------

-- Request Synology API
-- http://stackoverflow.com/questions/11167289/simulation-login-using-lua
-- https://code.google.com/p/facepunch-lua-sdk/source/browse/trunk/connectors/luasocket.lua?spec=svn46&r=46
function requestAPI (lul_device, apiName, method, version, parameters)
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
	--if (pluginParams.sessionId ~= nil) then
	--	url = url .. "&_sid=" .. pluginParams.sessionId
	--end
	-- Optionnal parameters
	if (parameters ~= nil) then
		for parameterName, value in pairs(parameters) do
			url = url .. "&" .. parameterName .. "=" .. tostring(value)
		end
	end

	debug("requestAPI", "Call : " .. url)

	local data = {}
	local status = -1
	local response
	local b, code, headers = -1, ""
	local requestBody = {}
	local responseBody = {}
	local nbTry = 0
	local isFatalError = false
	while ((status ~= 0) and not isFatalError and (nbTry < pluginParams.nbMaxRetry)) do
		-- Call Synology API
		--status, response = luup.inet.wget(url, pluginParams.requestTimeout)
		--local response, status = http.request(url)
		--response, code, responseHeaders = http.request({
		-- code == 200
		response = {}
		b, code, headers = http.request({
			url = url,
			--source = ltn12.source.string(requestBody),
			headers = {
				cookie = "id=" .. tostring(pluginParams.sessionId)
			},
  			sink = ltn12.sink.table(response)
		})
		--debug("requestAPI", "Response status : " .. tostring(status))
		debug("requestAPI", "Response b:" .. tostring(b) .. " - code: " .. tostring(code))
		if ((not b) or (code ~= 200)) then
			-- HTTP error
			showErrorOnUI("requestAPI", lul_device, "HTTP error - code:" .. tostring(code) .. " - response:" .. tostring(response), true)
		else
			--debug("requestAPI", "Response  : " .. json.encode(response))
			-- Search sessionId in cookie if exist
			--pluginParams.sessionId = nil
			for k, v in pairs(headers) do
				--debug("requestAPI", "Response header : " .. tostring(k) .. "=" .. tostring(v))
				if (k == "set-cookie") then
					pluginParams.sessionId = string.match(v, "id=([^;,]*)")
					break
				end
			end
			debug("requestAPI", "Session Id: " .. tostring(pluginParams.sessionId))

			response = table.concat(response, "")
			response = response:gsub("%[%]","[null]") -- Trick for library "json.lua" (UI5)
			local decodeSuccess, jsonResponse = pcall(json.decode, response)
			if (not decodeSuccess) then
				showErrorOnUI("requestAPI", lul_device, "Response decode error: " .. tostring(jsonResponse), true)
				debug("requestAPI", "Response: " .. tostring(response))
			else
--debug("requestAPI", "jsonResponse: " .. json.encode(jsonResponse))
				if (jsonResponse.success) then
					status = 0
					data = jsonResponse.data
					debug("requestAPI", "Data: " .. json.encode(data))
				else
					-- API error
					status = -1
					local errorCode, errorMessage = tonumber(jsonResponse.error.code), "unkown"
					if ((API_ERROR_CODE[apiName] ~= nil) and (API_ERROR_CODE[apiName][errorCode] ~= nil)) then
						errorMessage = API_ERROR_CODE[apiName][errorCode][1]
						isFatalError = API_ERROR_CODE[apiName][errorCode][2]
					elseif (API_ERROR_CODE["common"][errorCode] ~= nil) then
						errorMessage = API_ERROR_CODE["common"][errorCode][1]
						isFatalError = API_ERROR_CODE[apiName][errorCode][2]
					end
					showErrorOnUI("requestAPI", lul_device, "API error: "  .. tostring(errorMessage) .. " (" .. tostring(errorCode) .. ")", false)
				end
			end
		end
		if not isFatalError then
			nbTry = nbTry + 1
			if ((status ~= 0) and (nbTry < pluginParams.nbMaxRetry)) then
				luup.sleep(5000)
				debug("requestAPI", "retry #" .. tostring(nbTry))
				resetError()
				showErrorOnUI("requestAPI", lul_device, "Retry #" .. tostring(nbTry), false)
			end
		end
	end

	return status, data
end

-- Query APIs’ information (no login required)
function retrieveApiInfo (lul_device)
	local status, data = requestAPI(lul_device, "SYNO.API.Info", "Query", 1, {
		--query = "SYNO.API.Auth,SYNO.SurveillanceStation.Info,SYNO.SurveillanceStation.Camera,SYNO.SurveillanceStation.ExternalEvent,SYNO.SurveillanceStation.ExternalRecording"
		query = "SYNO.API.Auth,SYNO.SurveillanceStation.Info,SYNO.SurveillanceStation.Camera,SYNO.SurveillanceStation.Camera.Wizard,SYNO.SurveillanceStation.ExternalEvent,SYNO.SurveillanceStation.ExternalRecording"
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
			else
				showErrorOnUI("retrieveApiInfo", lul_device, "Can't retrieve Surveillance Station version", true)
			end

			return true
		else
			showErrorOnUI("retrieveApiInfo", lul_device, "Synology API version is too old - DSM 4.0-2251 and Surveillance Station 6.1 are required", true)
		end
	else
		showErrorOnUI("retrieveApiInfo", lul_device, "Can't connect to Synology host", true)
	end
	return false
end

-- Session login
function login (lul_device)
	debug("login", "Try to log in")
	pluginParams.sessionId = nil
	local status, data = requestAPI(lul_device, "SYNO.API.Auth", "Login", 2, {
		account = pluginParams.userName,
		passwd  = pluginParams.password,
		session = "SurveillanceStation",
		format  = "cookie"
	})
	if ((status == 0) and (pluginParams.sessionId ~= nil)) then
		log("login", "Session is opened - SID : " .. pluginParams.sessionId)
		return true
	else
		showErrorOnUI("login", lul_device, "Login failed", false)
		return false
	end
end

-- Session logout
function logout (lul_device)
	debug("logout", "Try to log out")
	local status, data = requestAPI(lul_device, "SYNO.API.Auth", "Logout", 2, { session = "SurveillanceStation" })
	if (status == 0) then
		pluginParams.sessionId = nil
		log("logout", "Session is closed")
		return true
	else
		showErrorOnUI("logout", lul_device, "Logout failed", false)
		return false
	end
end

-- Get quota informations
function retrieveQuota (lul_device)
	debug("retrieveQuota", "Retrieve quota informations")
	local status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.Camera.Wizard", "CheckQuota", 1, {})
	if (status == 0) then
		pluginParams.quota = {
			localCamNum = tonumber(data.localCamNum) or 0,
			iKeyUsed = tonumber(data.iKeyUsed) or 0,
			iKeyTotal = tonumber(data.iKeyTotal) or 0
		}
		if ((pluginParams.quota.iKeyTotal == 0) or (pluginParams.quota.localCamNum > pluginParams.quota.iKeyTotal)) then
			-- TODO : check if this can detect if the licence has expired
			showErrorOnUI("retrieveQuota", lul_device, "Problem with licence", true)
			return false
		end
		return true
	else
		showErrorOnUI("retrieveQuota", lul_device, "Can't get quota", false)
		return false
	end
end

-- 
function updateCamerasStatuses (lul_device)
	-- Save camera list
	local cameraList = {}
	for _, camera in ipairs(pluginParams.cameras) do
		log("retrieveCameras", "Get camera #" .. tostring(camera.id) .. " '" .. camera.name .. "'")
		table.insert(cameraList, tostring(camera.id) .. "," .. tostring(camera.name) .. "," .. tostring(camera.status) .. "," .. tostring(camera.recStatus))
	end
	setVariable(lul_device, SID.SurveillanceStationRemote, "Cameras", table.concat(cameraList, "|"))
end

-- Get camera list (require login)
function retrieveCameras (lul_device)
	debug("retrieveCameras", "Retrieve cameras")
	local status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.Camera", "List", 2, {
		--limit = 10,
		additional = "device"
	})
	if (status == 0) then
		pluginParams.cameras = data.cameras
		updateCamerasStatuses(lul_device)
		return true
	else
		showErrorOnUI("retrieveCameras", lul_device, "Can't get camera list", false)
		return false
	end
end

-- Update statuses of Surveillance Station Remote
function updateStatuses (lul_device)
	-- Compute statuses
	local status = "0"
	local recordStatus = "0"
	for _, camera in pairs(pluginParams.cameras) do
		if ((camera.status == 0) or (camera.status == 2)) then
			-- At least one camera is enabled or is about to be enabled
			status = "1"
		end
		if (camera.recStatus == 6) then
			-- At least one camera is external recording
			recordStatus = "1"
		end
	end
	setVariable(lul_device, SID.SwitchPower, "Status", status)
	setVariable(lul_device, SID.SurveillanceStationRemote, "Record", recordStatus)
end

function getCameraIds (lul_device)
	local cameraIds = {}
	for _, camera in pairs(pluginParams.cameras) do
		table.insert(cameraIds, camera.id)
	end
	return cameraIds
end

function getActiveCameraIds (lul_device)
	local cameraIds = {}
	for _, camera in pairs(pluginParams.cameras) do
		if (camera.status == 0) then
			table.insert(cameraIds, camera.id)
		end
	end
	return cameraIds
end

function getRecordingCameraIds (lul_device)
	local cameraIds = {}
	for _, camera in pairs(pluginParams.cameras) do
		if (camera.recStatus > 0) then
			table.insert(cameraIds, camera.id)
		end
	end
	return cameraIds
end

function getCameraById (lul_device, cameraId)
	for _, camera in pairs(pluginParams.cameras) do
		if (tonumber(camera.id) == tonumber(cameraId)) then
			return camera
		end
	end
	error("getCameraById", "Camera #" .. tostring(cameraId) .. " is unknown")
	return nil
end

function setBusy (lul_device, shouldBeBusy)
	if (not luup.is_ready(lul_device)) then
		debug("isBusy", "Device is not ready")
		showMessageOnUI(lul_device, "Device is not ready...")
		return false
	end
	if (shouldBeBusy and pluginParams.isBusy) then
		debug("isBusy", "Still processing")
		showMessageOnUI(lul_device, "Still processing...")
		return false
	end
	pluginParams.isBusy = shouldBeBusy
	return true
end

function resetError ()
	pluginParams.lastError = ""
	setVariable(lul_device, SID.SurveillanceStationRemote, "LastError", "")
end

function handleError (lul_device)
	if (pluginParams.lastError == "") then
		setVariable(lul_device, SID.SurveillanceStationRemote, "CommFailure", "0")
		setVariable(lul_device, SID.SurveillanceStationRemote, "CommFailureTime", "0")
		return false
	else
		setVariable(lul_device, SID.SurveillanceStationRemote, "CommFailure", "1")
		setVariable(lul_device, SID.SurveillanceStationRemote, "CommFailureTime", os.time())
		-- TODO
		-- http://wiki.mios.com/index.php/Alerts
		--http://IP:3480/data_request?id=add_alert&device=DEVICE_ID&type=3&source=3&description=ALERT_DESCRIPTION
		local url = require("socket.url")
		local alertDescription = "Communication issue with Surveillance station on " .. tostring(pluginParams.protocol) .. "://" .. tostring(pluginParams.host) .. ":" ..  tostring(pluginParams.port)
		--local status, response = luup.inet.wget('/data_request?id=add_alert&device=' .. tostring(lul_device) .. '&type=3&source=3&description=' .. url.escape(alertDescription))

		return true
	end
end

-------------------------------------------
-- External event management
-------------------------------------------

-------------------------------------------
-- Main functions
-------------------------------------------

-- TODO - Disable a camera if out of order
function setOptions (lul_device, lul_settings)
	local options = lul_settings.newOptions or "{}"
	local decodeSuccess, jsonOptions = pcall(json.decode, options)
	if (not decodeSuccess) then
		showErrorOnUI("setOptions", lul_device, "Options decode error: " .. tostring(jsonOptions))
		debug("setOptions", "Options: " .. tostring(options))
	else

	end
end

-- Update Surveillance Station informations
function update (lul_device, lul_settings)
	debug("update", "Update")
	resetError()

	if (not setBusy(lul_device, true)) then
		return
	end

	if (login(lul_device)) then
		if retrieveCameras(lul_device) then
			updateStatuses(lul_device)
		end
		logout(lul_device)
	end
	if (not handleError(lul_device)) then
		setVariable(lul_device, SID.SurveillanceStationRemote, "LastUpdate", os.time())
		showStatusOnUI(lul_device)
	end

	setBusy(lul_device, false)
end

-- Enable or disable cameras (list or all)
function setTarget (lul_device, lul_settings)
	local method, cameraIdList
	resetError()

	if (not setBusy(lul_device, true)) then
		-- TODO : request queue
		showMessageOnUI(lul_device, "Remote is busy...")
		handleError(lul_device)
		return
	end

	-- Method name
	if ((lul_settings.newTargetValue ~= nil) and (tostring(lul_settings.newTargetValue) == "0")) then
		method = "Disable"
	else
		method = "Enable"
	end
	-- Get camera ids list or compute it
	cameraIdList = lul_settings.cameraIds or lul_settings.cameraId or table.concat(getCameraIds(lul_device), ",")

	debug("setTarget", method .. " camera(s) #" .. tostring(cameraIdList))
	showMessageOnUI(lul_device, method .. " camera(s) #" .. tostring(cameraIdList) .. "...")
	if (login(lul_device)) then
		local status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.Camera", method, 3, {
			cameraIds = tostring(cameraIdList)
		})
		if (status == 0) then
			-- Update the status of the cameras
			if (type(data.data.camera) == "table") then
				for _, dataCamera in pairs(data.data.camera) do
					local camera = getCameraById(lul_device, dataCamera.id)
					if (camera ~= nil) then
						if dataCamera.enabled then
							camera.status = 0
						else
							camera.status = 1
						end
					end
				end
			end
			--retrieveCameras(lul_device)
			updateStatuses(lul_device)
			updateCamerasStatuses(lul_device)
		end
		logout(lul_device)
	end
	if (not handleError(lul_device)) then
		setVariable(lul_device, SID.SurveillanceStationRemote, "LastUpdate", os.time())
		showStatusOnUI(lul_device)
	end

	setBusy(lul_device, false)
end

-- Start or stop external record on one camera
function setRecordTarget (lul_device, lul_settings)
	local deviceStatus, action
	local cameraIds

	if (not setBusy(lul_device, true)) then
		return
	end

	if (luup.variable_get(SID.SwitchPower, "Status", lul_device) ~= "1") then
		debug("setRecordTarget", "Device is disable : do nothing")
		showMessageOnUI(lul_device, "Device is disable : do nothing")
		return
	end

	-- Action name
	if (tostring(lul_settings.newRecordTargetValue) == "1") then
		action = "start"
	else
		action = "stop"
	end
	-- Camera ids
	if (lul_settings.cameraId ~= nil) then
		--cameraIds = { [[lul_settings.cameraId]] }
		local cameraId = lul_settings.cameraId
		cameraIds = { cameraId }
	else
		cameraIds = getCameraIds(lul_device)
	end

	showMessageOnUI(lul_device, action .. " record for camera(s) #" .. tostring(table.concat(cameraIds, ",")) .. "...")
	resetError()
	if (login(lul_device)) then
		local result = true
		for _, cameraId in pairs(cameraIds) do
			debug("setRecordTarget", action .. " record for camera #" .. tostring(cameraId))
			local status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.ExternalRecording", "Record", 2, {
				cameraId = cameraId,
				action = action
			})
			if (status ~= 0) then
				result = false
				break
			else
				local camera = getCameraById(lul_device, cameraId)
				if (action == "start") then
					camera.recStatus = 6
				else
					camera.recStatus = 0
				end
			end
		end
		if (result) then
			if (table.getn(getRecordingCameraIds(lul_device)) > 0) then
				setVariable(lul_device, SID.SurveillanceStationRemote, "Record", "1")
			else
				setVariable(lul_device, SID.SurveillanceStationRemote, "Record", "1")
			end
		end
		logout(lul_device)
	end
	if (not handleError(lul_device)) then
		setVariable(lul_device, SID.SurveillanceStationRemote, "LastUpdate", os.time())
		showStatusOnUI(lul_device)
	end

	setBusy(lul_device, false)
end

-- Trigger external event
function triggerExternalEvent (lul_device, lul_settings)
	local eventId = tonumber(lul_settings.eventId) or 0

	if ((eventId < 1) or (eventId > 10)) then
		showErrorOnUI("triggerExternalEvent", lul_device, "Event id '" .. tostring(lul_settings.eventId) .. "' is not in (1-10)", true)
		return
	end

	if (not setBusy(lul_device, true)) then
		return
	end

	debug("triggerExternalEvent", "Trigger event #" .. tostring(eventId))
	showMessageOnUI(lul_device, "Trigger event #" .. tostring(eventId) .. "...")
	resetError()
	if (login(lul_device)) then
		local status, data = requestAPI(lul_device, "SYNO.SurveillanceStation.ExternalEvent", "Trigger", 1, {
			eventId = eventId
		})
		if (status == 0) then
			-- TODO : gérer évènement non transmis
			showMessageOnUI(lul_device, "Event #" .. tostring(eventId) .. " sent")
		end
		logout(lul_device)
	end
	if (not handleError(lul_device)) then
		showMessageOnUI(lul_device, "Event #" .. tostring(eventId) .. " has been triggered")
	end

	setBusy(lul_device, false)
end

-------------------------------------------
-- Startup
-------------------------------------------

-- Init plugin instance
function initPluginInstance (lul_device)
	log("initPluginInstance", "Init")

	local isInitialized = true

	-- Get plugin params for this device
	getVariableOrInit(lul_device, SID.SwitchPower, "Status", "0")
	getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Record", "0")
	getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Message", "")
	getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "CommFailure", "0")
	getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "CommFailureTime", "0")
	getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "LastError", "")
	getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "LastUpdate", "")
	pluginParams = {
		apiInfo        = {},
		apiVersion     = "",
		protocol       = getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Protocol", "http"),
		host           = getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Host", "diskstation"),
		port           = getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Port", "5000"),
		userName       = getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "UserName", ""),
		password       = getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Password", ""),
		cameras        = getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Cameras", ""),
		nbMaxRetry     = tonumber(getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "NbMaxRetry", NB_MAX_RETRY)) or NB_MAX_RETRY,
		requestTimeout = tonumber(getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Timeout", REQUEST_TIMEOUT)) or REQUEST_TIMEOUT,
		debugMode      = (getVariableOrInit(lul_device, SID.SurveillanceStationRemote, "Debug", "0") == "1"),
		isBusy         = false
	}
	resetError()

	-- Check settings
	if ((pluginParams.userName == "") or (pluginParams.password == "")) then
		showErrorOnUI("initPluginInstance", lul_device, "Variables 'UserName' and 'Password' must be set", true)
		isInitialized = false
	-- Try to get API infos
	elseif (
		not retrieveApiInfo(lul_device)
		or not login(lul_device)
		or not retrieveQuota(lul_device)
		or not retrieveCameras(lul_device)
	) then
		isInitialized = false
	end
	updateStatuses(lul_device)

	-- Log out
	logout(lul_device)

	if (not handleError(lul_device)) then
		setVariable(lul_device, SID.SurveillanceStationRemote, "LastUpdate", os.time())
		showStatusOnUI(lul_device)
		pluginParams.isBusy = false
	end

	return isInitialized
end

function startup (lul_device)
	log("startup", "Start plugin '" .. PLUGIN_NAME .. "' (v" .. PLUGIN_VERSION .. ")")

	if (type(json) == "string") then
		showErrorOnUI("startup", lul_device, "No JSON decoder", true)
		return false, "No JSON decoder"
	end

	-- Update static JSON file
	if updateStaticJSONFile(lul_device, PLUGIN_NAME .. "1") then
		warning("startup", "'device_json' has been updated : reload LUUP engine")
		luup.reload()
		return false, "Reload LUUP engine"
	end

	-- Init
	initPluginInstance(lul_device)

	-- Watch setting changes
	luup.variable_watch("initPluginInstance", SID.SurveillanceStationRemote, "Protocol", lul_device)
	luup.variable_watch("initPluginInstance", SID.SurveillanceStationRemote, "Host", lul_device)
	luup.variable_watch("initPluginInstance", SID.SurveillanceStationRemote, "Port", lul_device)
	luup.variable_watch("initPluginInstance", SID.SurveillanceStationRemote, "UserName", lul_device)
	luup.variable_watch("initPluginInstance", SID.SurveillanceStationRemote, "Password", lul_device)
	luup.variable_watch("onDebugValueIsUpdated", SID.SurveillanceStationRemote, "Debug", lul_device)

	if (luup.version_major >= 7) then
		luup.set_failure(0, lul_device)
	end

	return true
end
