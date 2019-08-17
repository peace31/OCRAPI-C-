
/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
*/

var exec = require('cordova/exec');


/**
 * The Capture interface exposes an interface to the camera and microphone of the hosting device.
 */
function Capture1() {
}


/**
 * Launches a recognize of OCR.
 *
 * @param (DOMString} type
 * @param {Function} successCallback
 * @param {Function} errorCallback
 * @param {OcrOptions} options
 */
function _recognize(type, successCallback, errorCallback, options) {
    var win = function(pluginResult) {
        successCallback(pluginResult);
    };
    exec(win, errorCallback, "Capture1", type, [options]);
}

/**
 * Launch device camera application for recgnize ocr.
 *
 * @param {Function} successCallback
 * @param {Function} errorCallback
 * @param {OcrOptions} options
 */
Capture1.prototype.StartOCR = function(successCallback, errorCallback, options){
    _recognize("startOCR", successCallback, errorCallback, options);
};

/**
 * Stop device camera application
 *
 */
Capture1.prototype.StopOCR = function(successCallback, errorCallback){
    _recognize("stopOCR", successCallback, errorCallback);
};
module.exports = new Capture1();

