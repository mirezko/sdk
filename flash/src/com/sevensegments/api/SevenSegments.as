package com.sevensegments.api {
	
	import flash.net.URLRequest;
	import flash.net.URLLoader;
	import flash.utils.getQualifiedClassName;
	import flash.net.SharedObject;
	import flash.utils.Timer;
	
	public class SevenSegments {

		private const DEFAULT_TARGET:String = 'http://api.7segments.com';
		private const TRACKING_COOKIE_KEY:String = '__7S_etc__';
		private const ONLINE_CHECK_DELAY:int = 10 * 60; // 10 min
		
		private var initialized:Boolean = false;
		private var timeInitialized:Boolean = false;
		private var config:Object;
		private var defaultProperties:* = {};
		private var processing:Boolean = false;
		private var queue:Array = [];
		private var pingTimer:Timer = null;
		private var isOnline:Boolean = true;
		private var onlineCheckTimer:Timer = null;
		private var lastCommand:Function = null;
		private var resendTimeoutBase:int = 1000;
		private var resendTimeout:int = resendTimeoutBase;
		private var resendTimeoutFactor:int = 2;
		private var resendTimeoutMax:int = 60 * 60 * 1000;
		private var lastUsedTimestamp:* = null;
		private var duplicateTimestampIncrement:Number = 0.001;
		private var timestampOffset:int = 0; // server timestamp - client timestamp
		private var resendTimer:Timer = null;
		
		public function SevenSegments() {
			this.initialized = false;
			this.config = {
				target: DEFAULT_TARGET,
				token: null,
				customer: {
					cookie: getCookie()
				},
				ping: {
					enabled: true,
					interval: 2 * 60,
					properties: {}
				},
				debug: false,
				offlineOnError: false
			};
		}

		private function guid():* {
            return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c:*):* {
                var r:* = Math.random() * 16 | 0;
                var v:* = (c == 'x') ? r : (r & 0x3 | 0x8);
                return v.toString(16);
            });
        }
		
		private function getCookie():String {
			var so:SharedObject  = SharedObject.getLocal(TRACKING_COOKIE_KEY);
			if (so.size == 0 || !so.data.cookie || (typeof so.data.cookie) !== 'string' || so.data.cookie.length != 36) {
				so.data.cookie = guid();
				so.flush();
			}
			return so.data.cookie;
		}
		
		private function processNext():void {
			if (!isOnline && lastCommand !== null) {
				queue.unshift(lastCommand);
				lastCommand = null;
				processing = false;
				return;
			}
			lastCommand = null;
			if (queue.length == 0) {
				processing = false;
				return;
			}
			lastCommand = queue[0];
			lastCommand();
		}
		
		private function processedSuccess():void {
			queue.shift();
			resendTimeout = resendTimeoutBase;
			processNext();
		}
		
		private function retryResend(action:Function):void {
			resendTimeout *= resendTimeoutFactor;
			if (resendTimeout > resendTimeoutMax) {
				resendTimeout = resendTimeoutMax;
			}
			this.debug('timing out for ' + resendTimeout + ' ms');
			if (resendTimer != null) {
				resendTimer.stop();
				resendTimer = null;
			}
			resendTimer = new Timer(resendTimeout, 1);
			resendTimer.addEventListener('timer', function():* {
				resendTimer.stop();
				resendTimer = null;
				action();
			});
			resendTimer.start();
		}
		
		private function processedError():void {
			retryResend(processNext);
		}

		private function processQueue():void {
			if (!isOnline) return;
			if (!timeInitialized) return;
			if (processing) return;
			processing = true;
			processNext();
		}

		private function enqueue(processor:*):void {
			queue.push(function():* {
				processor(processedSuccess, processedError);
			});
			if (initialized) processQueue();
		}
		
		private function queryTime():void {
			if (timeInitialized) return;
			
			var clientTS:* = getTimestamp();
			
			var req:URLRequest = new URLRequest();
			req.method = 'GET';
			req.url = config.target + '/system/time?clientTS=' + clientTS;
			
			loadRequest(req, function(json:*):* {
				var serverTS:* = json.time;
				var clientTS2:* = getTimestamp();
				var avgClientTS:* = clientTS2 - (clientTS2 - clientTS) / 2;
				timestampOffset = serverTS - avgClientTS;
				debug('time offset is ' + timestampOffset);
				resendTimeout = resendTimeoutBase;
				timeInitialized = true;
				processQueue();
			}, function():* {
				retryResend(queryTime);
			});
		}
		
		private function getTimestamp():Number {
			var now:Number = new Date().time / 1000;
			if (lastUsedTimestamp != null && lastUsedTimestamp >= now) {
				now = lastUsedTimestamp + duplicateTimestampIncrement;
			}
			lastUsedTimestamp = now;
			return now;
		}

		private function preProcessCustomerIds(options:Object):void {
			if (options.customer is String) {
				options.customer = {registered: options.customer};
			}
			if (!options.customer) return;
			if ('cookie' in options.customer) {
				delete options.customer.cookie;
			}
		}

		private function getCustomerJson(properties:*):* {
			return {
				ids: config.customer,
				company_id: config.token,
				properties: properties
			};
		}

		private function toJSON(o:Object):String {
			return JSON.stringify(o);
		}
		
		private function fromJSON(s:String):Object {
			return JSON.parse(s);
		}
		
		private function prepareRequest(path:String, data:Object):URLRequest {
			var req:URLRequest = new URLRequest();
			req.contentType = 'application/json';
			req.method = 'POST';
			req.url = config.target + path;
			req.data = toJSON(data);
			return req;
		}
		
		private function loadRequest(req:URLRequest, successCallback:Function, errorCallback:Function):void {
			var loader:URLLoader = new URLLoader();
			var httpStatus:* = null;
			loader.addEventListener('httpResponseStatus', function(ev:*):* {
				httpStatus = ev.status;
				debug('Received response status code: ', httpStatus);
			});
			loader.addEventListener('complete', function(ev:*):void {
				debug('Received response: ', loader.data);
				if (httpStatus !== null && httpStatus != 200) {
					if (config.offlineOnError && httpStatus == 0) {
						offline();
					}
					errorCallback();
					return;
				}
				var parsed:Object;
				try {
					parsed = fromJSON(loader.data);
				}
				catch (error:Error) {
					debug('Error parsing JSON response');
					errorCallback();
					return;
				}
				successCallback(parsed);
			});
			loader.addEventListener('ioError', function(ev:*):* {
				debug('Cannot connect to server.');
				if (config.offlineOnError) offline();
				errorCallback();
			});
			loader.addEventListener('securityError', function(ev:*):* {
				debug('Cannot connect to server due to security error.');
				errorCallback();
			});
			loader.load(req);
		}
		
		private function updateCustomer(customerProperties:Object, successCallback:Function, errorCallback:Function):void {
			var customer:* = getCustomerJson(customerProperties);
			var req:URLRequest = prepareRequest('/crm/customers', customer);
			loadRequest(req, function(data:*):* {
				successCallback();
			}, errorCallback);
		}

		private function debug(message:String, data:* = undefined):void {
			if (!config.debug) return;
			var date:* = (new Date()).toUTCString();
			trace('7S [' + date + '] ' + message);
			if (data !== undefined) trace(toJSON(data));
		}
		
		private function getPingParams():Object {
			return this.extend({}, this.config.ping.properties);
		}

		private function sendPing():void {
			if (config.ping.enabled) {
				this.track('customer_ping', this.getPingParams());
			}
		}

		private function setupPingTimer():void {
			if (pingTimer != null) {
				pingTimer.stop();
				pingTimer = null;
			}
			if (config.ping.enabled && isOnline) {
				pingTimer = new Timer(config.ping.interval * 1000);
				pingTimer.addEventListener('timer', function():* {
					sendPing();
				});
				pingTimer.start();
			}
		}
		
		private function pingCallback(successCallback:Function, errorCallback:Function):void {
			sendPing();
			setupPingTimer();
			successCallback();
		}
		
		private function setupOnlineCheckTimer():void {
			if (onlineCheckTimer != null) {
				onlineCheckTimer.stop();
				onlineCheckTimer = null;
			}
			if (!isOnline) {
				onlineCheckTimer = new Timer(ONLINE_CHECK_DELAY * 1000, 1);
				onlineCheckTimer.addEventListener('timer', function():* {
					online();
				});
				onlineCheckTimer.start();
			}
		}
		
		private function extend(... args):Object {
			for (var i:int = 1; i < args.length; i++) {
				for (var key:* in args[i]) {
					if (args[i][key] == null) continue;
					if (args[0][key] === args[i][key]) continue;					
					
					if (getQualifiedClassName(args[0][key]) == 'Object') {
						args[0][key] = extend({}, args[0][key], args[i][key]);
					}
					else if (getQualifiedClassName(args[0][key]) == 'Array') {
						args[0][key] = extend([], args[0][key], args[i][key]);
					}
					else if (args[i][key] !== undefined) {
						args[0][key] = args[i][key];
					}
				}
			}
			return args[0];
		}
		
		public function initialize(options:Object):void {
			if (initialized) {
				trace('7S already initialized');
				return;
			}
            preProcessCustomerIds(options);
			extend(config, options);
			if (!(config.token is String)) {
                trace('Invalid format of 7Segments token.');
                return;
            }
            initialized = true;
            debug('Initializing', config);
            if (!config.ping.enabled) this.identify(config.customer);
            enqueue(pingCallback);
            queryTime();
        }

        public function identify(customerIds:Object = null, customerProperties:Object = null):void {
            if (customerIds != null) {
                if (customerIds is String) {
                    customerIds = {registered: customerIds};
                }
            }
			else {
				customerIds = {};
			}
			if (customerProperties == null) customerProperties = {};
            enqueue(function(successCallback:*, errorCallback:*):* {
                customerIds['cookie'] = config.customer.cookie;
                config.customer = customerIds;
                debug('Identifying customer: ', customerIds);
                debug('Updating customer: ', customerProperties);
                updateCustomer(customerProperties, successCallback, errorCallback);
            });
        }

        public function update(customerProperties:Object):void {
            enqueue(function(successCallback:*, errorCallback:*):* {
                debug('Updating customer', customerProperties);
                updateCustomer(customerProperties, successCallback, errorCallback);
            });
        }

        public function track(eventType:String, eventProperties:Object = null):void {
			if (eventProperties == null) {
				eventProperties = {};
			}
			var rawTimestamp:Number = getTimestamp();
            enqueue(function(successCallback:*, errorCallback:*):* {
                var event:* = {
                    customer_ids: config.customer,
                    company_id: config.token,
                    type: eventType,
					timestamp: rawTimestamp + timestampOffset,
                    properties: extend({}, defaultProperties, eventProperties || {})
                };
                debug('Tracking event: ' + eventType, eventProperties);
				
				var req:URLRequest = prepareRequest('/crm/events', event);
				loadRequest(req, function(data:*):* {
					successCallback();
				}, errorCallback);
            });
        }

        public function evaluate(... arguments):void {
            var campaigns:* = [];
            var customerProperties:* = {};
            var evaluationCallback:* = function (arg:*):* {};
            for (var i:int = 0; i < arguments.length; i++) {
				var typ:* = getQualifiedClassName(arguments[i]);
                if (typ == 'Function') evaluationCallback = arguments[i];
                if (typ == 'Object') customerProperties = arguments[i];
                if (typ == 'Array') campaigns = arguments[i];
                if (typ == 'String') campaigns = [arguments[i]];
            }
            enqueue(function(successCallback:*, errorCallback:*):* {
                var ajaxCallback:* = function(response:*):* {
                    var arg:* = (campaigns.length == 1) ? response[campaigns[0]] : response;
                    evaluationCallback(arg);
                    successCallback();
                };
                debug('Evaluating customer: ', customerProperties);
                var evaluation:* = getCustomerJson(customerProperties);
                evaluation['campaigns'] = campaigns;
				
				var req:URLRequest = prepareRequest('/campaigns/automated/evaluate', evaluation);
				loadRequest(req, ajaxCallback, errorCallback);
            });
        }

        public function ping(pingConfig:*):void {
            debug('Changing ping configuration: ', pingConfig);
            extend(config.ping, pingConfig);
			enqueue(pingCallback);
        }
		
		private function offline():void {
			debug('We are offline, suspending queue');
			isOnline = false;
			setupPingTimer();
			setupOnlineCheckTimer();
		}
		
		private function online():void {
			debug('Resuming queue processing');
			isOnline = true;
			setupPingTimer();
			setupOnlineCheckTimer();
			processQueue();
		}

	}
	
}
