//@ sourceURL=J_SurveillanceStationRemote1.js

var SurveillanceStationRemote = (function (api, $) {

	var uuid = 'ToBeDefined';
	var SurveillanceStationRemote_SID = 'urn:upnp-org:serviceId:SurveillanceStationRemote1';
	var myModule = {};

	// UI5 compatibility
	if (api === null) {
		api = {
			setCpanelContent: function (html) {
				set_panel_html(html);
			}		
		};
	}
	// UI5 compatibility
	if (typeof Utils === 'undefined') {
		window.Utils = {
			logError: function (message) {
				console.error(message);
			}
		};
	}

	/**
	 * Get camera list
	 */
	function getCameraList (deviceId) {
		var cameras = [];
		get_device_state(deviceId, SurveillanceStationRemote_SID, "Cameras", 1)
			.split("|")
			.forEach(function(value) {
				var cameraDatas = value.split(",")
				var camera = {
					id:        cameraDatas[0],
					name:      cameraDatas[1],
					status:    cameraDatas[2],
					recStatus: cameraDatas[3] 
				}
				cameras.push(camera);
			});
		return cameras;
	}

	/**
	 * Draw and manage camera list
	 */
	function drawCameraList (deviceId, cameras) {
		$("#SSR_camerasList").empty();
		$.each(cameras, function(i, camera) {
			$("#SSR_camerasList").append(
					'<div data-camera_id="' + camera.id + '">'
				+		'<span class="SSR_camera_name">'
				+			i + '. ' + camera.name
				+		'</span>'
				+		'<button class="SSR-enable ui-widget-content ui-corner-all' + (camera.status != "5" ? ' ui-state-active' : '') + '">Enable</button>'
				+		'<button class="SSR-record ui-widget-content ui-corner-all' + (camera.recStatus > "0" ? ' ui-state-active' : '') + '">REC</button>'
				+	'</div>'
			);
		});
		$("#SSR_camerasList span").css({
			"display": "inline-block",
			"width": "300px"
		});
		$("#SSR_camerasList button")
			.click(function () {
				var cameraId = $(this).parent().data("camera_id");
				var url = "id=lu_action&output_format=json&DeviceNum=" + deviceId + "&serviceId=" + SurveillanceStationRemote_SID;
				if ($(this).is(".SSR-enable")) {	
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
			api.setCpanelContent(
					'<div id="SSR_camerasList">'
				+		"The plugin is not configured. Please go in tab 'Advanced'"
				+	'</div>'
			);

			var cameras = getCameraList(deviceId);
			if (cameras.length > 0) {
				drawCameraList(deviceId, cameras);
			}
		} catch (err) {
			Utils.logError('Error in SurveillanceStationRemote.showCameras(): ' + err);
		}
	}

	myModule = {
		uuid: uuid,
		showCameras: showCameras
	};
	return myModule;

})((typeof api !== 'undefined' ? api : null), jQuery);

// UI5 compatibility
var SurveillanceStationRemote_showCameras = SurveillanceStationRemote.showCameras;
