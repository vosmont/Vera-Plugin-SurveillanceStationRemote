//# sourceURL=J_SurveillanceStationRemote1.js

/**
 * This file is part of the plugin SurveillanceStationRemote.
 * https://github.com/vosmont/Vera-Plugin-SurveillanceStationRemote
 * Copyright (c) 2016 Vincent OSMONT
 * This code is released under the MIT License, see LICENSE.
 */

/**
 * UI5 compatibility with JavaScript API for UI7
 * http://wiki.micasaverde.com/index.php/JavaScript_API
 */
( function( $ ) {
	if ( !window.Utils ) {
		window.Utils = {
			logError: function( message ) {
				console.error( message );
			},
			logDebug: function( message ) {
				console.info( message );
			}
		};
	}
	if ( !window.api ) {
		window.api = {
			version: "UI5",
			API_VERSION: 6,

			getCommandURL: function() {
				return command_url;
			},
			getDataRequestURL: function() {
				return data_request_url;
			},
			getSendCommandURL: function() {
				return data_request_url.replace('port_3480/data_request','port_3480');
			},

			getListOfDevices: function() {
				return jsonp.ud.devices;
			},
			getRoomObject: function( roomId ) {
				roomId = roomId.toString();
				for ( var i = 0; i < jsonp.ud.rooms.length; i++ ) {
					var room = jsonp.ud.rooms[ i ];
					if ( room.id.toString() === roomId ) {
						return room;
					}
				}
			},
			setCpanelContent: function( html ) {
				set_panel_html( html );
			},
			getDeviceStateVariable: function( deviceId, service, variable, options ) {
				return get_device_state( deviceId, service, variable, ( options.dynamic === true ? 1: 0 ) );
			},
			setDeviceStateVariable: function( deviceId, service, variable, value, options ) {
				set_device_state( deviceId, service, variable, value, ( options.dynamic === true ? 1: 0 ) );
			},
			setDeviceStateVariablePersistent: function( deviceId, service, variable, value, options ) {
				set_device_state( deviceId, service, variable, value, 0 );
			},
			performActionOnDevice: function (deviceId, service, action, options) {
				var query = "id=lu_action&DeviceNum=" + deviceId + "&serviceId=" + service + "&action=" + action;
				$.each( options.actionArguments, function( key, value ) {
					query += "&" + key + "=" + value;
				});
				$.ajax( {
					url: data_request_url + query,
					success: function( data, textStatus, jqXHR ) {
						if ( $.isFunction( options.onSuccess ) ) {
							options.onSuccess( {
								responseText: jqXHR.responseText,
								status: jqXHR.status
							} );
						}
					},
					error: function( jqXHR, textStatus, errorThrown ) {
						if ( $.isFunction( options.onFailure ) ) {
							options.onFailure( {
								responseText: jqXHR.responseText,
								status: jqXHR.status
							} );
						}
					}
				});
			},
			registerEventHandler: function( eventName, object, functionName ) {
				// Not implemented in UI5
			},

			showLoadingOverlay: function() {
				if ( $.isFunction( show_loading ) ) {
					show_loading();
				}
				return $.Deferred().resolve();
			},
			hideLoadingOverlay: function() {
				if ( $.isFunction( hide_loading ) ) {
					hide_loading();
				}
				return true;
			},
			showCustomPopup: function( content, opt ) {
				var autoHide = 'undefined' != typeof opt && 'undefined' != typeof opt.autoHide ? parseFloat(1000 * opt.autoHide) : 0,
				 category = 'undefined' != typeof opt && 'undefined' != typeof opt.category ? opt.category : void 0,
				 beforeShow = 'undefined' != typeof opt && 'function' == typeof opt.beforeShow ? opt.beforeShow : void 0,
				 afterShow = 'undefined' != typeof opt && 'function' == typeof opt.afterShow ? opt.afterShow : void 0,
				 onHide = 'undefined' != typeof opt && 'function' == typeof opt.onHide ? opt.onHide : void 0,
				 afterHide = 'undefined' != typeof opt && 'function' == typeof opt.afterHide ? opt.afterHide : void 0,
				 onSuccess = 'undefined' != typeof opt && 'function' == typeof opt.onSuccess ? opt.onSuccess : void 0,
				 onCancel = 'undefined' != typeof opt && 'function' == typeof opt.onCancel ? opt.onCancel : void 0;
					
					
					
			},

			getVersion: function() {
				return api.API_VERSION;
			},
			requiresVersion: function( minVersion, opt_fnFailure ) {
				console.log( "minVersion:", minVersion, "API Version:", api.API_VERSION );
				if ( api.API_VERSION < parseInt( minVersion, 10 ) ) {
					if ( $.isFunction( opt_fnFailure ) ) {
						return opt_fnFailure( api.API_VERSION );
					} else {
						Utils.logError( "WARNING ! This plugin requires at least API version " + minVersion + " !" );
					}
				}
			}
		};
	}
	// UI7 fix
	Utils.getDataRequestURL = function() {
		var dataRequestURL = api.getDataRequestURL();
		if ( dataRequestURL.indexOf( "?" ) === -1 ) {
			dataRequestURL += "?";
		}
		return dataRequestURL;
	};
	// Custom CSS injection
	Utils.injectCustomCSS = function( nameSpace, css ) {
		if ( $( "style[title=\"" + nameSpace + " custom CSS\"]" ).size() === 0 ) {
			Utils.logDebug( "Injects custom CSS for " + nameSpace );
			var pluginStyle = $( "<style>" );
			if ($.fn.jquery === "1.5") {
				pluginStyle.attr( "type", "text/css" )
					.attr( "title", nameSpace + " custom CSS" );
			} else {
				pluginStyle.prop( "type", "text/css" )
					.prop( "title", nameSpace + " custom CSS" );
			}
			pluginStyle
				.html( css )
				.appendTo( "head" );
		} else {
			Utils.logDebug( "Injection of custom CSS has already been done for " + nameSpace );
		}
	};
} ) ( jQuery );

var SurveillanceStationRemote = ( function( api, $ ) {

	var _uuid = '33894758-b77b-47e9-b4ff-fd01c54814c9';
	var _deviceId = null;

	var _terms = {
		"Explanation for cameras": "\
TODO"
	};

	function _T( t ) {
		var v =_terms[ t ];
		if ( v ) {
			return v;
		}
		return t;
	}

	// Inject plugin specific CSS rules
	Utils.injectCustomCSS( "SurveillanceStationRemote", '\
.ssr-panel { padding: 5px; }\
.ssr-panel label { font-weight: normal }\
.ssr-panel td { padding: 5px; }\
.ssr-panel .icon { vertical-align: middle; }\
.ssr-panel .icon.big { vertical-align: sub; }\
.ssr-panel .icon:before { font-size: 15px; }\
.ssr-panel .icon.big:before { font-size: 30px; }\
.ssr-panel .icon-help:before { content: "\\2753"; }\
.ssr-panel .icon-refresh:before { content: "\\267B"; }\
.ssr-panel .icon-map:before { content: "\\25F1"; }\
.ssr-hidden { display: none; }\
.ssr-error { color:red; }\
.ssr-header { margin-bottom: 15px; font-size: 1.1em; font-weight: bold; }\
.ssr-explanation { margin: 5px; padding: 5px; border: 1px solid; background: #FFFF88}\
.ssr-toolbar { height: 25px; text-align: right; }\
.ssr-toolbar button { display: inline-block; }\
.ssr-camera { display: inline-block; margin: 5px; }\
.ssr-camera button.ui-state-active { background: #006e46 !important; }\
.ssr-camera button.ui-state-hover { background: #d9d6d6 !important; }\
#ssr-donate { text-align: center; width: 70%; margin: auto; }\
#ssr-donate form { height: 50px; }\
'
	);

	// *************************************************************************************************
	// Tools
	// *************************************************************************************************

	/**
	 * Convert a unix timestamp into date
	 */
	function _convertTimestampToLocaleString( timestamp ) {
		if ( typeof( timestamp ) === "undefined" ) {
			return "";
		}
		var t = new Date( parseInt( timestamp, 10 ) * 1000 );
		var localeString = t.toLocaleString();
		return localeString;
	}
	function _convertTimestampToIsoString( timestamp ) {
		if ( typeof( timestamp ) === "undefined" ) {
			return "";
		}
		var t = new Date( parseInt( timestamp, 10 ) * 1000 );
		var isoString = t.toISOString();
		return isoString;
	}

	// *************************************************************************************************
	// Cameras
	// *************************************************************************************************

	/**
	 * Get cameras
	 */
	function _getCamerasAsync() {
		var d = $.Deferred();
		api.showLoadingOverlay();
		$.ajax( {
			url: Utils.getDataRequestURL() + "id=lr_SurveillanceStationRemote_" + _deviceId + "&command=getCameras&output_format=json#",
			dataType: "json"
		} )
		.done( function( cameras ) {
			api.hideLoadingOverlay();
			if ( $.isArray( cameras ) ) {
				d.resolve( cameras );
			} else {
				Utils.logError( "No cameras" );
				d.reject();
			}
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			api.hideLoadingOverlay();
			Utils.logError( "Get cameras error : " + errorThrown );
			d.reject();
		} );
		return d.promise();
	}

	function _updateSnapshot( cameraId ) {
		$("#ssr-cameras .ssr-camera[data-cameraid='" + cameraId + "'] img")
			.attr( "src", Utils.getDataRequestURL() + "id=lr_SurveillanceStationRemote_" + _deviceId + "&command=getSnapshot&cameraId=" + cameraId + "&timestamp=" + ( new Date() ).getTime() );
	}

	/**
	 * Draw and manage camera list
	 */
	function _drawCameraList() {
		if ( $( "#ssr-cameras" ).length === 0 ) {
			return;
		}
		$.when( _getCamerasAsync() )
			.done( function( cameras ) {
				if ( cameras.length > 0 ) {
					var html = '';
					$.each( cameras, function( i, camera ) {
						html += '<table class="ssr-camera" data-cameraid="' + camera.id + '">'
							+		'<tr>'
							+			'<td>'
							+				'<div class="ssr-camera-name">'
							+					i + '. ' + camera.name
							+				'</div>'
							+				'<img class="ssr-camera-snapshot" src="" height="100">'
							+			'</td>'
							+			'<td>'
							+				'<button class="ssr-enable ui-widget-content ui-corner-all' + ( camera.status != "5" ? ' ui-state-active' : '' ) + '">Enable</button>'
							+				'<button class="ssr-record ui-widget-content ui-corner-all' + ( camera.recStatus > "0" ? ' ui-state-active' : '' ) + '">REC</button>'
							+			'</td>'
							+		'</tr>'
							+	'</table>';
					});
					$("#ssr-cameras").html( html );
					$.each( cameras, function( i, camera ) {
						_updateSnapshot( camera.id );
					} );
				}  else {
					$("#ssr-cameras").html( "There's no camera." );
				}
			} );
	}

	/**
	 * Show camera list
	 */
	function _showCameras( deviceId ) {
		_deviceId = deviceId;
		try {
			api.setCpanelContent(
				'<div id="ssr-cameras-panel" class="ssr-panel">'
				+		'<div class="ssr-toolbar">'
				+			'<button type="button" class="ssr-help"><span class="icon icon-help"></span>Help</button>'
				+			'<button type="button" class="ssr-refresh"><span class="icon icon-refresh"></span>Refresh</button>'
				+		'</div>'
				+		'<div class="ssr-explanation ssr-hidden">'
				+			_T( "Explanation for cameras" )
				+		'</div>'
				+		'<div id="ssr-cameras">'
				+		'</div>'
				+	'</div>'
			);

			// Manage UI events
			$( "#ssr-cameras-panel" )
				.on( "click", ".ssr-help" , function() {
					$( ".ssr-explanation" ).toggleClass( "ssr-hidden" );
				} )
				.on( "click", ".ssr-refresh", function() {
					_drawCameraList();
				} );
			$("#ssr-cameras")
				.delegate( "button", "click", function( event ) {
					var cameraId = $( this ).parents( ".ssr-camera:first" ).data( "cameraid" );
					var target = "";
					if ( $( this ).is( ".ui-state-active" ) ) {
						target = "0";
						$( this ).removeClass( "ui-state-active" );
					} else {
						target = "1";
						$( this ).addClass( "ui-state-active" );
					}
					if ( $(this).is( ".ssr-enable" ) ) {
						_performActionSetTarget( cameraId, target );
					} else if ( $(this).is( ".ssr-record" ) ) {
						_performActionSetRecordTarget( cameraId, target );
					}
				})
				.delegate( "button", "mouseover", function( event ) {
					$( this ).addClass( "ui-state-hover" );
				})
				.delegate( "button", "mouseout", function( event ) {
					$( this ).removeClass( "ui-state-hover" );
				});

			// Display the cameras
			_drawCameraList();
		} catch (err) {
			Utils.logError( "SurveillanceStationRemote.showCameras(): " + err );
		}
	}

	// *************************************************************************************************
	// Actions
	// *************************************************************************************************

	/**
	 * 
	 */
	function _performActionSetTarget( cameraId, target ) {
		Utils.logDebug( "[SurveillanceStationRemote.performActionSetTarget] Set target '" + target + "' for camera #" + cameraId );
		api.performActionOnDevice( _deviceId, "urn:upnp-org:serviceId:SwitchPower1", "SetTarget", {
			actionArguments: {
				output_format: "json",
				cameraId: cameraId,
				newTargetValue: target
			}
		});
	}

	/**
	 * 
	 */
	function _performActionSetRecordTarget( cameraId, recordTarget ) {
		Utils.logDebug( "[SurveillanceStationRemote.performActionSetRecordTarget] Set record target '" + recordTarget + "' for camera #" + cameraId );
		api.performActionOnDevice( _deviceId, "urn:upnp-org:serviceId:SurveillanceStationRemote1", "SetRecordTarget", {
			actionArguments: {
				output_format: "json",
				cameraId: cameraId,
				newRecordTargetValue: recordTargetValue
			}
		});
	}

	// *************************************************************************************************
	// Errors
	// *************************************************************************************************

	/**
	 * Get errors
	 */
	function _getErrorsAsync() {
		var d = $.Deferred();
		api.showLoadingOverlay();
		$.ajax( {
			url: Utils.getDataRequestURL() + "id=lr_SurveillanceStationRemote_" + _deviceId + "&command=getErrors&output_format=json#",
			dataType: "json"
		} )
		.done( function( errors ) {
			api.hideLoadingOverlay();
			if ( $.isArray( errors ) ) {
				d.resolve( errors );
			} else {
				Utils.logError( "No errors" );
				d.reject();
			}
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			api.hideLoadingOverlay();
			Utils.logError( "Get errors error : " + errorThrown );
			d.reject();
		} );
		return d.promise();
	}

	/**
	 * Draw errors list
	 */
	function _drawErrorsList() {
		if ( $( "#ssr-errors" ).length === 0 ) {
			return;
		}
		$.when( _getErrorsAsync() )
			.done( function( errors ) {
				if ( errors.length > 0 ) {
					var html = '<table><tr><th>Date</th><th>Error</th></tr>';
					$.each( errors, function( i, error ) {
						html += '<tr>'
							+		'<td>' + _convertTimestampToLocaleString( error[0] ) + '</td>'
							+		'<td>' + error[1] + '</td>'
							+	'</tr>';
					} );
					html += '</table>';
					$("#ssr-errors").html( html );
				} else {
					$("#ssr-errors").html("There's no error.");
				}
			} );
	}

	/**
	 * Show errors tab
	 */
	function _showErrors( deviceId ) {
		_deviceId = deviceId;
		try {
			api.setCpanelContent(
					'<div id="ssr-errors-panel" class="ssr-panel">'
				+		'<div id="ssr-errors">'
				+		'</div>'
				+	'</div>'
			);
			// Display the errors
			_drawErrorsList();
		} catch (err) {
			Utils.logError('Error in SurveillanceStationRemote.showErrors(): ' + err);
		}
	}

	// *************************************************************************************************
	// Donate
	// *************************************************************************************************

	function _showDonate( deviceId ) {
		var donateHtml = '\
<form action="https://www.paypal.com/cgi-bin/webscr" method="post" target="_blank">\
<input type="hidden" name="cmd" value="_s-xclick">\
<input type="hidden" name="encrypted" value="-----BEGIN PKCS7-----MIIHZwYJKoZIhvcNAQcEoIIHWDCCB1QCAQExggEwMIIBLAIBADCBlDCBjjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRYwFAYDVQQHEw1Nb3VudGFpbiBWaWV3MRQwEgYDVQQKEwtQYXlQYWwgSW5jLjETMBEGA1UECxQKbGl2ZV9jZXJ0czERMA8GA1UEAxQIbGl2ZV9hcGkxHDAaBgkqhkiG9w0BCQEWDXJlQHBheXBhbC5jb20CAQAwDQYJKoZIhvcNAQEBBQAEgYBO/FN7wNo83fPycYs1DGsT9OqtipGv/sduqG9rgBQM/XdnK/uOGpD42aFTx/SyoEVU4qR0bP72n2j7QCTB7riHmkeBwIz2onZP1Zivh9G7p884SCwWD8iT6r8E7SRTG95vc4s81PL5hI9WEYW20mTAlGMBPrVXAWjQpTj9igMpoTELMAkGBSsOAwIaBQAwgeQGCSqGSIb3DQEHATAUBggqhkiG9w0DBwQIinmEQtnUtxqAgcBVM4BR4UzpMYil8SzputDc7TGo8R6kPHmCy8+9It3LSv2Glz4o5jGTiHqcNPrH2UQvd6OfaCgpsD9aSXhwdtMVXhLY/1jqjoeKGmnzFNAYiaLpes9QL3vs4yzwOKR9EAK8u8cAbD36yRv/oITSMKnXSr3zhxvpUv4Nl7/P7rSc+Ya207jC2QosO3HHQABibfxnRUZpkXlQjlTvHC6KdfAkcs+YRR72Kwk+DFAMvHAY7aNegfx3Fik1XvfcIs5XfDKgggOHMIIDgzCCAuygAwIBAgIBADANBgkqhkiG9w0BAQUFADCBjjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRYwFAYDVQQHEw1Nb3VudGFpbiBWaWV3MRQwEgYDVQQKEwtQYXlQYWwgSW5jLjETMBEGA1UECxQKbGl2ZV9jZXJ0czERMA8GA1UEAxQIbGl2ZV9hcGkxHDAaBgkqhkiG9w0BCQEWDXJlQHBheXBhbC5jb20wHhcNMDQwMjEzMTAxMzE1WhcNMzUwMjEzMTAxMzE1WjCBjjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRYwFAYDVQQHEw1Nb3VudGFpbiBWaWV3MRQwEgYDVQQKEwtQYXlQYWwgSW5jLjETMBEGA1UECxQKbGl2ZV9jZXJ0czERMA8GA1UEAxQIbGl2ZV9hcGkxHDAaBgkqhkiG9w0BCQEWDXJlQHBheXBhbC5jb20wgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAMFHTt38RMxLXJyO2SmS+Ndl72T7oKJ4u4uw+6awntALWh03PewmIJuzbALScsTS4sZoS1fKciBGoh11gIfHzylvkdNe/hJl66/RGqrj5rFb08sAABNTzDTiqqNpJeBsYs/c2aiGozptX2RlnBktH+SUNpAajW724Nv2Wvhif6sFAgMBAAGjge4wgeswHQYDVR0OBBYEFJaffLvGbxe9WT9S1wob7BDWZJRrMIG7BgNVHSMEgbMwgbCAFJaffLvGbxe9WT9S1wob7BDWZJRroYGUpIGRMIGOMQswCQYDVQQGEwJVUzELMAkGA1UECBMCQ0ExFjAUBgNVBAcTDU1vdW50YWluIFZpZXcxFDASBgNVBAoTC1BheVBhbCBJbmMuMRMwEQYDVQQLFApsaXZlX2NlcnRzMREwDwYDVQQDFAhsaXZlX2FwaTEcMBoGCSqGSIb3DQEJARYNcmVAcGF5cGFsLmNvbYIBADAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBBQUAA4GBAIFfOlaagFrl71+jq6OKidbWFSE+Q4FqROvdgIONth+8kSK//Y/4ihuE4Ymvzn5ceE3S/iBSQQMjyvb+s2TWbQYDwcp129OPIbD9epdr4tJOUNiSojw7BHwYRiPh58S1xGlFgHFXwrEBb3dgNbMUa+u4qectsMAXpVHnD9wIyfmHMYIBmjCCAZYCAQEwgZQwgY4xCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJDQTEWMBQGA1UEBxMNTW91bnRhaW4gVmlldzEUMBIGA1UEChMLUGF5UGFsIEluYy4xEzARBgNVBAsUCmxpdmVfY2VydHMxETAPBgNVBAMUCGxpdmVfYXBpMRwwGgYJKoZIhvcNAQkBFg1yZUBwYXlwYWwuY29tAgEAMAkGBSsOAwIaBQCgXTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0xNjA2MDIxNzEzNTRaMCMGCSqGSIb3DQEJBDEWBBSHkUxN3P8F7QMI8s55f51zuewNXTANBgkqhkiG9w0BAQEFAASBgARjeqgEqm48KkuApjLzUYo6TD507bLlsDrIYVqAf84MuqrCbpFrrcwvoFg63HhIs8LhbMVR+EPwbgKxunjWAORuSHK7eJu/EDe8o9xmC2taDgUJjzOvTeT7Jrwpg3gF0ks8iC7eKTVujMvquOa3Wq70+VuL85pShfZ1GUHddXEC-----END PKCS7-----">\
<input type="image" src="https://www.paypalobjects.com/en_US/FR/i/btn/btn_donateCC_LG.gif" border="0" name="submit" alt="PayPal - The safer, easier way to pay online!">\
<img alt="" border="0" src="https://www.paypalobjects.com/fr_FR/i/scr/pixel.gif" width="1" height="1">\
</form>';

		api.setCpanelContent(
				'<div id="ssr-donate-panel" class="ssr-panel">'
			+		'<div id="ssr-donate">'
			+			'<span>This plugin is free but if you install and find it useful then a donation to support further development is greatly appreciated</span>'
			+			donateHtml
			+		'</div>'
			+	'</div>'
		);
	}

	// *************************************************************************************************
	// Main
	// *************************************************************************************************

	/**
	 * Callback on device events
	 */
	function _onDeviceStatusChanged( deviceObjectFromLuStatus ) {
		if ( deviceObjectFromLuStatus.id === _deviceId ) {
			for ( i = 0; i < deviceObjectFromLuStatus.states.length; i++ ) { 
				if (deviceObjectFromLuStatus.states[i].variable === "Cameras") {
					var cameras = getCameraList( _deviceId, deviceObjectFromLuStatus.states[ i ].value );
					drawCameraList( deviceId, cameras );
				} else if ( deviceObjectFromLuStatus.states[ i ].variable === "Status" ) {
					// TODO
				}
			}
		}
	}

	var myModule = {
		uuid: _uuid,
		onDeviceStatusChanged: _onDeviceStatusChanged,
		showCameras: _showCameras,
		showErrors: _showErrors,
		showDonate: _showDonate
	};

	// Register
	api.registerEventHandler( "on_ui_deviceStatusChanged", myModule, "onDeviceStatusChanged" );

	// UI5 compatibility
	if ( api.version === "UI5" ) {
		window[ "SurveillanceStationRemote.showCameras" ] = showCameras;
	}

	return myModule;

})( api, jQuery );
