---
title: OCR & recognization
description: Detect text from camera in real time and recognize pairs of key and value specified by parameter.
---
<!--
# license: Licensed to the Apache Software Foundation (ASF) under one
#         or more contributor license agreements.  See the NOTICE file
#         distributed with this work for additional information
#         regarding copyright ownership.  The ASF licenses this file
#         to you under the Apache License, Version 2.0 (the
#         "License"); you may not use this file except in compliance
#         with the License.  You may obtain a copy of the License at
#
#           http://www.apache.org/licenses/LICENSE-2.0
#
#         Unless required by applicable law or agreed to in writing,
#         software distributed under the License is distributed on an
#         "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#         KIND, either express or implied.  See the License for the
#         specific language governing permissions and limitations
#         under the License.
-->

# cordova-plugin-doc-detect

This plugin provides OCR real time from camera.


This plugin defines global `window.capture.docRecognize` object.

Although in the global scope, it is not available until after the `deviceready` event.

    document.addEventListener("deviceready", onDeviceReady, false);
    function onDeviceReady() {
        console.log(window.capture.docRecognize);
    }


## Installation
    cordova plugin add ../custom_plugins/OCR_cordova_plugin --variable CAMERA_USAGE_DESCRIPTION="Requires access to the camera"

    cordova plugin add https://github.com/yyc93/OCR_cordova_plugin.git --variable CAMERA_USAGE_DESCRIPTION="Requires access to the camera"

This plugin checked with android SDK 26. So you can add android platform 7.0.0.


## Custom Configration in iOS for Phonetic Text Engine

    In order to use Phonet Engine module, you have to add this items in ios platform tag in config.xml for custom cofigure after installing cordova-custom-config plugin in your project.

        <custom-preference buildType="debug" name="ios-XCBuildConfiguration-GCC_INPUT_FILETYPE" value="sourcecode.cpp.objcpp" xcconfigEnforce="true" />
        <custom-preference buildType="debug" name="ios-XCBuildConfiguration-CLANG_CXX_LANGUAGE_STANDARD" value="gnu++0x" xcconfigEnforce="true" />
        <custom-preference buildType="debug" name="ios-XCBuildConfiguration-CLANG_CXX_LIBRARY" value="libc++" xcconfigEnforce="true" />
        <custom-preference buildType="release" name="ios-XCBuildConfiguration-GCC_INPUT_FILETYPE" value="sourcecode.cpp.objcpp" xcconfigEnforce="true" />
        <custom-preference buildType="release" name="ios-XCBuildConfiguration-CLANG_CXX_LANGUAGE_STANDARD" value="gnu++0x" xcconfigEnforce="true" />
        <custom-preference buildType="release" name="ios-XCBuildConfiguration-CLANG_CXX_LIBRARY" value="libc++" xcconfigEnforce="true" />
    
    And have to also add one line in root tag
        <preference name="cordova-custom-config-autorestore" value="false" />

## Supported Platforms

- Android
- iOS

## Objects

- Capture1
- OcrOptions

## Methods

- capture.docRecognize

## Properties

## window.capture.docRecognize

> Start the Doc recognization application and return information about Recognized text.

    window.capture.docRecognize(
        CaptureCB captureSuccess, CaptureErrorCB captureError,  [OcrOptions options]
    );

### Description

Starts an asynchronous detection of ocr and recognized the text to match with keys and patterns

### Supported Platforms

- Android
- iOS

### Example

    // capture callback
    var captureSuccess = function(mediaFiles) {
        console.log(result);   
    };

    // capture error callback
    var captureError = function(error) {
        console.error("Error code: ", error.code);
    };

    // start OCR
    window.capture.docRecognize(captureSuccess, captureError, {debug:true});

### iOS Quirks

Since iOS 10 it's mandatory to add a `NSCameraUsageDescription` in the info.plist.

* `NSCameraUsageDescription` describes the reason that the app accesses the user’s camera.library.

When the system prompts the user to allow access, this string is displayed as part of the dialog box.

To add this entry you can pass the following variables on plugin install.

* `CAMERA_USAGE_DESCRIPTION` for `NSCameraUsageDescription`

-
Example:

`cordova plugin add https://github.com/yyc93/OCR_cordova_plugin.git --variable CAMERA_USAGE_DESCRIPTION="your usage message"`

If you don't pass the variable, the plugin will add an empty string as value.


## OcrOptions

> Encapsulates ocr configuration options.

### Properties

- __debug__: the debug state. If want to debug, true. Otherwise false.

- __country__: the country name of address type.

- __dictionary__: The key name and patterns for recognization of Text.

### Example

    // debug mode and Australia address of invoice
    var options = {
            "country":"Australia",
            "debug":true,
            "dictionary":[
                {
                    "Name":"Account Name",
                    "Mandatory":true,
                    "Patterns":"^[a-zA-Z0-9\\s]+$",
                    "Keywords":["Account Name","Account Name"]
                }
            ]
        };

    window.capture.docRecognize(captureSuccess, captureError, options);

### iOS Quirks

- iOS supports an additional __licenseFileName__ property, to allow ABBYY mobile sdk license.
- iOS supports an additional __isFlashlightVisible__ property, to add flash button.
- iOS supports an additional __qstopWhenStable__ property, to allow stopping of recognization full text.
- iOS supports an additional __areaOfInterest__ property, to area of detection text.
- iOS supports an additional __isStopButtonVisible__ property, to visible stop button.

### Example ( iOS w/ quality )

    // limit capture operation to 1 video clip of low quality
    var options = {
            selectableRecognitionLanguages : ["English"],
            recognitionLanguages : ["English"],

            licenseFileName : "AbbyyRtrSdk.license",
            isFlashlightVisible : true,
            stopWhenStable : true,
            areaOfInterest : (0.8 + " " + 0.3),
            isStopButtonVisible : true,
        };
    window.capture.docRecognize(captureSuccess, captureError, options);

## Android Lifecycle Quirks

When capturing audio, video, or images on the Android platform, there is a chance that the
application will get destroyed after the Cordova Webview is pushed to the background by
the native capture application. See the [Android Lifecycle Guide][android-lifecycle] for
a full description of the issue. In this case, the success and failure callbacks passed
to the capture method will not be fired and instead the results of the call will be
delivered via a document event that fires after the Cordova [resume event][resume-event].

In your app, you should subscribe to the two possible events like so:

```javascript
function onDeviceReady() {
    // pendingcaptureresult is fired if the capture call is successful
    document.addEventListener('pendingcaptureresult', function(mediaFiles) {
        // Do something with result
    });

    // pendingcaptureerror is fired if the capture call is unsuccessful
    document.addEventListener('pendingcaptureerror', function(error) {
        // Handle error case
    });
}

// Only subscribe to events after deviceready fires
document.addEventListener('deviceready', onDeviceReady);
```

It is up you to track what part of your code these results are coming from. Be sure to
save and restore your app's state as part of the [pause][pause-event] and
[resume][resume-event] events as appropriate. Please note that these events will only
fire on the Android platform and only when the Webview was destroyed during a capture
operation.

[android-lifecycle]: http://cordova.apache.org/docs/en/latest/guide/platforms/android/index.html#lifecycle-guide
[pause-event]: http://cordova.apache.org/docs/en/latest/cordova/events/events.html#pause
[resume-event]: http://cordova.apache.org/docs/en/latest/cordova/events/events.html#resume
"# Crop_pro" 
