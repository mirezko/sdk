package com.sevensegments.api {
	
	import flash.net.URLRequest;
	import flash.net.URLLoader;
	import flash.utils.getQualifiedClassName;
	import flash.net.SharedObject;
	import flash.utils.Timer;
	
	public class SevenSegments {

		private const DEFAULT_TARGET = 'http://api.7segments.com';
		private const TRACKING_COOKIE_KEY = '__7S_etc__';
		private const ONLINE_CHECK_DELAY = 10 * 60; // 10 min
		
		private var initialized:Boolean = false;
		private var config:Object;
		private var defaultProperties = {};
		private var processing = false;
		private var queue = [];
		private var pingTimer:Timer = null;
		private var isOnline:Boolean = true;
		private var onlineCheckTimer:Timer = null;
		private var lastCommand:Function = null;
		
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
				debug: false
			};
		}

		private function guid() {
            return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                var r = Math.random() * 16 | 0;
                var v = (c == 'x') ? r : (r & 0x3 | 0x8);
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
		
		private function processNext() {
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
			lastCommand = queue.shift();
			lastCommand();
		}

		private function processQueue() {
			if (!isOnline) return;
			if (processing) return;
			processing = true;
			processNext();
		}

		private function enqueue(processor) {
			queue.push(function() {
				processor(processNext);
			});
			if (initialized) processQueue();
		}

		private function preProcessCustomerIds(options:Object) {
			if (options.customer is String) {
				options.customer = {registered: options.customer};
			}
			if (!options.customer) return;
			if ('cookie' in options.customer) {
				delete options.customer.cookie;
			}
		}

		private function getCustomerJson(properties) {
			return {
				ids: config.customer,
				company_id: config.token,
				properties: properties
			};
		}

		private function toJSON(o:Object) {
			return JSON.stringify(o);
		}
		
		private function fromJSON(s:String) {
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
		
		private function loadRequest(req:URLRequest, callback:Function) {
			var loader:URLLoader = new URLLoader();
			var httpStatus = null;
			loader.addEventListener('httpResponseStatus', function(ev) {
				httpStatus = ev.status;
				debug('Received response status code: ', httpStatus);
			});
			loader.addEventListener('complete', function(ev) {
				debug('Received response: ', loader.data);
				if (httpStatus !== null && httpStatus != 200) {
					callback();
					if (httpStatus == 0) {
						offline();
					}
					return;
				}
				callback();
			});
			loader.addEventListener('ioError', function(ev) {
				debug('Cannot connect to server.');
				offline();
				callback();
			});
			loader.addEventListener('securityError', function(ev) {
				debug('Cannot connect to server due to security error.');
				callback();
			});
			loader.load(req);
		}
		
		private function updateCustomer(customerProperties:Object, callback:Function) {
			var customer = getCustomerJson(customerProperties);
			var req:URLRequest = prepareRequest('/crm/customers', customer);
			loadRequest(req, callback);
		}

		private function debug(message:String, data:* = undefined) {
			if (!config.debug) return;
			var date = (new Date()).toUTCString();
			trace('7S [' + date + '] ' + message);
			if (data !== undefined) trace(toJSON(data));
		}
		
		private function getPingParams():Object {
			return this.extend({}, this.config.ping.properties);
		}

		private function sendPing() {
			if (config.ping.enabled) {
				this.track('customer_ping', this.getPingParams());
			}
		}

		private function setupPingTimer() {
			if (pingTimer != null) {
				pingTimer.stop();
				pingTimer = null;
			}
			if (config.ping.enabled && isOnline) {
				pingTimer = new Timer(config.ping.interval * 1000);
				pingTimer.addEventListener('timer', function() {
					sendPing();
				});
				pingTimer.start();
			}
		}
		
		private function pingCallback(callback:Function) {
			sendPing();
			setupPingTimer();
			callback();
		}
		
		private function setupOnlineCheckTimer() {
			if (onlineCheckTimer != null) {
				onlineCheckTimer.stop();
				onlineCheckTimer = null;
			}
			if (!isOnline) {
				onlineCheckTimer = new Timer(ONLINE_CHECK_DELAY * 1000, 1);
				onlineCheckTimer.addEventListener('timer', function() {
					online();
				});
				onlineCheckTimer.start();
			}
		}
		
		private function extend(... args):Object {
			for (var i:int = 1; i < args.length; i++) {
				for (var key in args[i]) {
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
		
		public function initialize(options:Object) {
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
            processQueue();
        }

        public function identify(customerIds:Object = null, customerProperties:Object = null) {
            if (customerIds != null) {
                if (customerIds is String) {
                    customerIds = {registered: customerIds};
                }
            }
			else {
				customerIds = {};
			}
			if (customerProperties == null) customerProperties = {};
            enqueue(function(callback) {
                customerIds['cookie'] = config.customer.cookie;
                config.customer = customerIds;
                debug('Identifying customer: ', customerIds);
                debug('Updating customer: ', customerProperties);
                updateCustomer(customerProperties, callback);
            });
        }

        public function update(customerProperties:Object) {
            enqueue(function(callback) {
                debug('Updating customer', customerProperties);
                updateCustomer(customerProperties, callback);
            });
        }

        public function track(eventType:String, eventProperties:Object = null) {
			if (eventProperties == null) {
				eventProperties = {};
			}
            enqueue(function(callback) {
                var event = {
                    customer_ids: config.customer,
                    company_id: config.token,
                    type: eventType,
                    properties: extend({}, defaultProperties, eventProperties || {})
                };
                debug('Tracking event: ' + eventType, eventProperties);
				
				var req:URLRequest = prepareRequest('/crm/events', event);
				loadRequest(req, callback);
            });
        }

        public function evaluate(... arguments) {
            var campaigns = [];
            var customerProperties = {};
            var evaluationCallback = function (arg) {};
            for (var i = 0; i < arguments.length; i++) {
				var typ = getQualifiedClassName(arguments[i]);
                if (typ == 'Function') evaluationCallback = arguments[i];
                if (typ == 'Object') customerProperties = arguments[i];
                if (typ == 'Array') campaigns = arguments[i];
                if (typ == 'String') campaigns = [arguments[i]];
            }
            enqueue(function(callback) {
                var ajaxCallback = function(response) {
                    var arg = (campaigns.length == 1) ? response[campaigns[0]] : response;
                    evaluationCallback(arg);
                    callback();
                };
                debug('Evaluating customer: ', customerProperties);
                var evaluation = getCustomerJson(customerProperties);
                evaluation['campaigns'] = campaigns;
				
				var req:URLRequest = prepareRequest('/campaigns/automated/evaluate', evaluation);
				
				var loader:URLLoader = new URLLoader();
				var httpStatus = null;
				loader.addEventListener('httpResponseStatus', function(ev) {
					httpStatus = ev.status;
					debug('Received response status code: ', httpStatus);
				});
				loader.addEventListener('complete', function(ev) {
					debug('Received response: ', loader.data);
					if (httpStatus !== null && httpStatus != 200) {
						callback();
						if (httpStatus == 0) {
							offline();
						}
						return;
					}
					var parsed:Object;
					try {
						parsed = fromJSON(loader.data);
					}
					catch (error:Error) {
						debug('Error parsing JSON response');
						callback();
						return;
					}
					ajaxCallback(parsed.data);
				});
				loader.addEventListener('ioError', function(ev) {
					debug('Cannot connect to server.');
					offline();
					callback();
				});
				loader.addEventListener('securityError', function(ev) {
					debug('Cannot connect to server due to security error.');
					callback();
				});
				loader.load(req);
            });
        }

        public function ping(pingConfig) {
            debug('Changing ping configuration: ', pingConfig);
            extend(config.ping, pingConfig);
			enqueue(pingCallback);
        }
		
		private function offline() {
			debug('We are offline, suspending queue');
			isOnline = false;
			setupPingTimer();
			setupOnlineCheckTimer();
		}
		
		private function online() {
			debug('Resuming queue processing');
			isOnline = true;
			setupPingTimer();
			setupOnlineCheckTimer();
			processQueue();
		}

	}
	
}
