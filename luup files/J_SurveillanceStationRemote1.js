//@ sourceURL=J_SurveillanceStationRemote1.js

var SurveillanceStationRemote = (function (api, $) {

	var uuid = '33894758-b77b-47e9-b4ff-fd01c54814c9';
	var SurveillanceStationRemote_SID = 'urn:upnp-org:serviceId:SurveillanceStationRemote1';
	var myModule = {};
	var _deviceId = null;

	// UI5 and ALTUI compatibility
	if (api === null) {
		api = {
			version: "UI5",
			getListOfDevices: function () {
				return jsonp.ud.devices;
			},
			setCpanelContent: function (html) {
				set_panel_html(html);
			},
			getDeviceStateVariable: function (deviceId, service, variable, options) {
				return get_device_state(deviceId, service, variable, (options.dynamic === true ? 1 : 0));
			},
			setDeviceStateVariable: function (deviceId, service, variable, value, options) {
				set_device_state(deviceId, service, variable, value, (options.dynamic === true ? 1 : 0));
			},
			setDeviceStateVariablePersistent: function (deviceId, service, variable, value, options) {
				set_device_state(deviceId, service, variable, value, 0);
			},
			performActionOnDevice: function (deviceId, service, action, options) {
				var query = "id=lu_action&DeviceNum=" + deviceId + "&serviceId=" + service + "&action=" + action;
				$.each(options.actionArguments, function (key, value) {
					query += "&" + key + "=" + value;
				});
				$.ajax({
					url: data_request_url + query,
					success: function (data, textStatus, jqXHR) {
						if (typeof (options.onSuccess) === 'function') {
							options.onSuccess({
								responseText: jqXHR.responseText,
								status: jqXHR.status
							});
						}
					},
					error: function (jqXHR, textStatus, errorThrown) {
						if (typeof (options.onFailure) != 'undefined') {
							options.onFailure({
								responseText: jqXHR.responseText,
								status: jqXHR.status
							});
						}
					}
				});
			},
			registerEventHandler: function (eventName, object, functionName) {
				// Not implemented
			}
		};
	}
	var myInterface = window.myInterface;
	if (typeof myInterface === 'undefined') {
		myInterface = {
			showModalLoading: function () {
				if ($.isFunction(show_loading)) {
					show_loading();
				}
			},
			hideModalLoading: function () {
				if ($.isFunction(hide_loading)) {
					hide_loading();
				}
			}
		};
	}
	var Utils = window.Utils;
	if (typeof Utils === 'undefined') {
		Utils = {
			logError: function (message) {
				console.error(message);
			},
			logDebug: function (message) {
				if ($.isPlainObject(window.AltuiDebug)) {
					AltuiDebug.debug(message);
				} else {
					//console.info(message);
				}
			}
		};
	}

	/**
	 * Update camera list according to external event
	 */
	function onDeviceStatusChanged (deviceObjectFromLuStatus) {
		if (deviceObjectFromLuStatus.id == _deviceId) {
			for (i = 0; i < deviceObjectFromLuStatus.states.length; i++) { 
				if (deviceObjectFromLuStatus.states[i].variable == "Cameras") {
					var cameras = getCameraList(_deviceId, deviceObjectFromLuStatus.states[i].value);
					drawCameraList(deviceId, cameras);
				} else if (deviceObjectFromLuStatus.states[i].variable == "Status") {
					// TODO
				}
			}
		}
	}

	/**
	 * Get camera list
	 */
	function getCameraList (deviceId, strCameras) {
		var cameras = [];
		if (typeof strCameras !== "string") {
			strCameras = get_device_state(deviceId, SurveillanceStationRemote_SID, "Cameras", 1);
		}
		strCameras
			.split("|")
			.forEach(function (value) {
				var cameraDatas = value.split(",");
				var camera = {
					id:        cameraDatas[0],
					name:      cameraDatas[1],
					status:    cameraDatas[2],
					recStatus: cameraDatas[3]
				};
				cameras.push(camera);
			});
		return cameras;
	}

	/**
	 * Draw and manage camera list
	 */
	function drawCameraList (deviceId, cameras) {
		$("#SurveillanceStationRemote_camerasList").empty();
		$.each(cameras, function (i, camera) {
			$("#SurveillanceStationRemote_camerasList").append(
					'<div data-camera_id="' + camera.id + '">'
				+		'<span class="SurveillanceStationRemote_camera_name">'
				+			i + '. ' + camera.name
				+		'</span>'
				+		'<button class="SurveillanceStationRemote-enable ui-widget-content ui-corner-all' + (camera.status != "5" ? ' ui-state-active' : '') + '">Enable</button>'
				+		'<button class="SurveillanceStationRemote-record ui-widget-content ui-corner-all' + (camera.recStatus > "0" ? ' ui-state-active' : '') + '">REC</button>'
				+	'</div>'
			);
		});
		$("#SurveillanceStationRemote_camerasList span").css({
			"display": "inline-block",
			"width": "300px"
		});
		$("#SurveillanceStationRemote_camerasList button")
			.click(function () {
				var cameraId = $(this).parent().data("camera_id");
				var url = "id=lu_action&output_format=json&DeviceNum=" + deviceId + "&serviceId=" + SurveillanceStationRemote_SID;
				if ($(this).is(".SurveillanceStationRemote-enable")) {
					url += "&action=SetTarget&newTargetValue=";
				} else {
					url += "&action=SetRecordTarget&newRecordTargetValue=";
				}
				if ($(this).is(".ui-state-active")) {
					url += "0";
					$(this).removeClass("ui-state-active");
				} else {
					url += "1";
					$(this).addClass("ui-state-active");
				}
				url += "&cameraId=" + cameraId + "&rand=" + Math.random();
				req.sendCommand(url, commandSent, null);
			})
			.hover(
				function () {
					$(this).addClass("ui-state-hover");
				}, function () {
					$(this).removeClass("ui-state-hover");
				}
			);
	}

	/**
	 * Show camera list
	 */
	function showCameras (deviceId) {
		try {
			_deviceId = deviceId;
			api.setCpanelContent(
					'<div id="SurveillanceStationRemote_camerasList">'
				+		"The plugin is not configured. Please go in tab 'Advanced'"
				+	'</div>'
			);

			var cameras = getCameraList(deviceId);
			if (cameras.length > 0) {
				drawCameraList(deviceId, cameras);
			}

			// Register
			api.registerEventHandler("on_ui_deviceStatusChanged", myModule, "onDeviceStatusChanged");
		} catch (err) {
			Utils.logError('Error in SurveillanceStationRemote.showCameras(): ' + err);
		}
	}

	myModule = {
		uuid: uuid,
		onDeviceStatusChanged: onDeviceStatusChanged,
		showCameras: showCameras
	};

	// UI5 compatibility
	if (api.version == "UI5") {
		window["SurveillanceStationRemote.showCameras"] = showCameras;
	}

	return myModule;

})((typeof api !== 'undefined' ? api : null), jQuery);
