/*
       Licensed to the Apache Software Foundation (ASF) under one
       or more contributor license agreements.  See the NOTICE file
       distributed with this work for additional information
       regarding copyright ownership.  The ASF licenses this file
       to you under the Apache License, Version 2.0 (the
       "License"); you may not use this file except in compliance
       with the License.  You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing,
       software distributed under the License is distributed on an
       "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
       KIND, either express or implied.  See the License for the
       specific language governing permissions and limitations
       under the License.
*/
package com.creative.informatics.camera;

import java.io.IOException;

import android.app.FragmentManager;
import android.app.FragmentTransaction;
import android.content.IntentFilter;
import android.os.Bundle;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.LOG;
import org.apache.cordova.PermissionHelper;
import com.creative.informatics.camera.PendingRequests.Request;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.PackageManager.NameNotFoundException;
import android.support.v4.content.LocalBroadcastManager;
import android.util.Log;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.widget.FrameLayout;

public class Capture1 extends CordovaPlugin implements BroadCastService.DetectResultCallbackInterface {
    private static final String TAG = Capture1.class.getSimpleName();

    private static final int RESULT_NOT_STARTED = -2;     // Constant for invalid stopping

    public static final int ACTION_RECOGNIZE_ID = 0;     // Constant for OCR recognize
    public static final int ACTION_RECOGNIZE_STOP = 2;     // Constant for DATA
    private static final int RECO_ERROR_FAILED = 3;
    private static final int RECO_ERROR_PERMISSION_DENIED = 4;
    private static final int RECO_ERROR_ALREADY_STARTED = 5;
    private static final int STOP_ERROR_ENGINE_NOT_STARTED = 6;

    public static final String ACTION_RECOGNIZED_ITEM   = "com.creative.informatics.detect.RECOGNIZED_ITEM";
    public static final String KEY_RESULT_DATA          = "com.creative.informatics.RESULT_DATA";

    private boolean cameraPermissionInManifest;     // Whether or not the CAMERA permission is declared in AndroidManifest.xml
    private BroadCastService broadcastService;
    private OcrCaptureFragment fragment;

    private ViewParent webViewParent;
    private int CONTAINER_VIEW_ID = 20; //<- set to random number to prevent conflict with other plugins

    private final PendingRequests pendingRequests = new PendingRequests();

    @Override
    protected void pluginInitialize() {
        super.pluginInitialize();

        // CB-10670: The CAMERA permission does not need to be requested unless it is declared
        // in AndroidManifest.xml. This plugin does not declare it, but others may and so we must
        // check the package info to determine if the permission is present.

        cameraPermissionInManifest = false;
        try {
            PackageManager packageManager = this.cordova.getActivity().getPackageManager();
            String[] permissionsInPackage = packageManager.getPackageInfo(this.cordova.getActivity().getPackageName(), PackageManager.GET_PERMISSIONS).requestedPermissions;
            if (permissionsInPackage != null) {
                for (String permission : permissionsInPackage) {
                    if (permission.equals(Manifest.permission.CAMERA)) {
                        cameraPermissionInManifest = true;
                        break;
                    }
                }
            }
        } catch (NameNotFoundException e) {
            // We are requesting the info for our package, so this should
            // never be caught
            LOG.e(TAG, "Failed checking for CAMERA permission in manifest", e);
        }
    }

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {

        if (action.equals("startOCR")) {
            JSONObject options = args.optJSONObject(0);

            return this.startOCR(pendingRequests.createRequest(ACTION_RECOGNIZE_ID, options, callbackContext));
        } else if( action.equals("stopOCR")) {
            return this.stopOCR(pendingRequests.createRequest(ACTION_RECOGNIZE_STOP, null, callbackContext));
        }

        return false;
    }

    /**
     * Sets up an intent to capture images.  Result handled by onActivityResult()
     */
    private boolean startOCR(Request req) {
        boolean needExternalStoragePermission =
                !PermissionHelper.hasPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE);

        boolean needExternalWStoragePermission =
                !PermissionHelper.hasPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE);

        boolean needCameraPermission = cameraPermissionInManifest &&
                !PermissionHelper.hasPermission(this, Manifest.permission.CAMERA);

        if (needExternalStoragePermission || needCameraPermission || needExternalWStoragePermission) {
            if(needExternalWStoragePermission && needExternalStoragePermission && needCameraPermission){
                PermissionHelper.requestPermissions(this, req.requestCode, new String[]{Manifest.permission.READ_EXTERNAL_STORAGE,Manifest.permission.WRITE_EXTERNAL_STORAGE, Manifest.permission.CAMERA});
            }
            else if (needExternalStoragePermission && needCameraPermission) {
                PermissionHelper.requestPermissions(this, req.requestCode, new String[]{Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.CAMERA});
            } else if (needExternalStoragePermission) {
                PermissionHelper.requestPermission(this, req.requestCode, Manifest.permission.READ_EXTERNAL_STORAGE);
            } else {
                PermissionHelper.requestPermission(this, req.requestCode, Manifest.permission.CAMERA);
            }
        } else {
            return docRecognize(req, req.options.optBoolean("toBack"));
        }

        return false;
    }

    private boolean docRecognize(Request req, final Boolean toBack) {

        if( broadcastService == null) {
            broadcastService = new BroadCastService(req.requestCode);
            broadcastService.setCallBack(this);
            IntentFilter filter = new IntentFilter(Capture1.ACTION_RECOGNIZED_ITEM);
            LocalBroadcastManager.getInstance(this.cordova.getActivity()).registerReceiver(broadcastService, filter);
        }

        /*Intent intent = new Intent(this.cordova.getActivity(), OcrCaptureActivity.class);
        intent.putExtra(OcrCaptureActivity.OCR_OPTION, req.options.toString());
        this.cordova.startActivityForResult(this, intent, req.requestCode);
        return true;*/
        Log.d(TAG, "start camera action");
        if (fragment != null) {
            pendingRequests.resolveWithFailure(req, createErrorObject(RECO_ERROR_ALREADY_STARTED, "Camera already started"));
            return true;
        }

        fragment = new OcrCaptureFragment();
        fragment.setOcrOptions(req.options.toString());
        //fragment.setEventListener(this);

        cordova.getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {


                //create or update the layout params for the container view
                FrameLayout containerView = cordova.getActivity().findViewById(CONTAINER_VIEW_ID);
                if(containerView == null){
                    containerView = new FrameLayout(cordova.getActivity().getApplicationContext());
                    containerView.setId(CONTAINER_VIEW_ID);

                    FrameLayout.LayoutParams containerLayoutParams =
                            new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
                    cordova.getActivity().addContentView(containerView, containerLayoutParams);
                }
                //display camera bellow the webview
                if(toBack){

                    webView.getView().setBackgroundColor(0x00000000);
                    webViewParent = webView.getView().getParent();
                    ((ViewGroup)webView.getView()).bringToFront();

                } else {
                    //set camera back to front
                    containerView.setAlpha(1);
                    containerView.bringToFront();
                }

                //add the fragment to the container
                FragmentManager fragmentManager = cordova.getActivity().getFragmentManager();
                FragmentTransaction fragmentTransaction = fragmentManager.beginTransaction();
                fragmentTransaction.add(containerView.getId(), fragment);
                fragmentTransaction.commit();
            }
        });

        return true;
    }

    private boolean stopOCR(Request req) {

        if(webViewParent != null) {
            cordova.getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    ((ViewGroup)webView.getView()).bringToFront();
                    webViewParent = null;
                }
            });
        }

        if( broadcastService != null) {
            LocalBroadcastManager.getInstance(this.cordova.getActivity())
                    .unregisterReceiver(broadcastService);
            broadcastService = null;
        }

        Request recoReq = pendingRequests.getLastRecognizeRequest();
        if( fragment == null){
            if( recoReq == null ){
                Log.e(TAG, "stopOCR: didn't find any request for this" );
                pendingRequests.resolveWithFailure(req, createErrorObject(STOP_ERROR_ENGINE_NOT_STARTED, "Camera is not started"));
            } else {
                pendingRequests.resolveWithSuccess(req);
            }
        } else {

            pendingRequests.resolveWithSuccess(req);

            FragmentManager fragmentManager = cordova.getActivity().getFragmentManager();
            FragmentTransaction fragmentTransaction = fragmentManager.beginTransaction();
            fragmentTransaction.remove(fragment);
            fragmentTransaction.commit();
            fragment = null;
        }

        return true;
    }

    private void onRecognizeActivityResult(Request req, Intent intent, boolean shouldBeFinish) {
        String data = null;

        if (intent != null){
            // Get json object for recognized data
            data = intent.getStringExtra(Capture1.KEY_RESULT_DATA);
        }

        req.results = new JSONArray();
        req.results.put(createRecognizedResult(data));
        pendingRequests.resolveWithSuccess(req, shouldBeFinish);
    }

    /**
     * Creates a JSONObject that represents a File from the Uri
     *
     * @param data the Uri of the audio/image/video
     * @return a JSONObject that represents a File
     * @throws IOException
     */
    private JSONObject createRecognizedResult(String data) {
        JSONObject obj = new JSONObject();
        JSONArray result;
        try {
            result = new JSONArray(data);
        } catch (JSONException e) {
            result = new JSONArray();
            e.printStackTrace();
        }
        try {
            obj.put("Detected Items", result);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return obj;
    }

    private JSONObject createErrorObject(int code, String message) {
        JSONObject obj = new JSONObject();
        try {
            obj.put("code", code);
            obj.put("message", message);
        } catch (JSONException e) {
            // This will never happen
        }
        return obj;
    }

    private void executeRequest(Request req) {
        switch (req.action) {
            case ACTION_RECOGNIZE_ID:
                this.startOCR(req);
                break;
        }
    }

    public void onRequestPermissionResult(int requestCode, String[] permissions,
                                          int[] grantResults) throws JSONException {
        Request req = pendingRequests.get(requestCode);

        if (req != null) {
            boolean success = true;
            for(int r : grantResults) {
                if (r == PackageManager.PERMISSION_DENIED) {
                    success = false;
                    break;
                }
            }

            if (success) {
                executeRequest(req);
            } else {
                pendingRequests.resolveWithFailure(req, createErrorObject(RECO_ERROR_PERMISSION_DENIED, "Permission denied."));
            }
        }
    }

    public Bundle onSaveInstanceState() {
        return pendingRequests.toBundle();
    }

    @Override
    public void onRestoreStateForActivityResult(Bundle state, CallbackContext callbackContext) {
        pendingRequests.setLastSavedState(state, callbackContext);
    }

    @Override
    public void onDetectResult(int requestCode, Intent intent) {
        Log.d(TAG, "onDetectResult: requestCode::"+requestCode );
        onProcessResult(requestCode, Activity.RESULT_OK, intent, false);
    }

    private void onProcessResult(int requestCode, int resultCode, final Intent intent, final boolean isFinished){
        final Request req = pendingRequests.get(requestCode);
        if (req == null) {
            Log.e(TAG, "onProcessResult: didn't find request for this action");
            return;
        }

        // Result received okay
        if (resultCode == Activity.RESULT_OK) {
            Runnable processActivityResult = new Runnable() {
                @Override
                public void run() {
                    switch(req.action) {
                        case ACTION_RECOGNIZE_ID:
                            onRecognizeActivityResult(req, intent,isFinished);
                            break;
                    }
                }
            };

            this.cordova.getThreadPool().execute(processActivityResult);
        } else if ( requestCode == RESULT_NOT_STARTED ){
            try {
                if (req.action == ACTION_RECOGNIZE_ID) {
                    pendingRequests.resolveWithFailure(req, createErrorObject(RECO_ERROR_FAILED, "Ocr engine is not started yet."));
                } else {
                    pendingRequests.resolveWithFailure(req, createErrorObject(RECO_ERROR_FAILED, "Unknown Action."));
                }
            } catch (Exception e){
                e.printStackTrace();
            }
        } else {
            try {
                if (req.action == ACTION_RECOGNIZE_ID) {
                    pendingRequests.resolveWithFailure(req, createErrorObject(RECO_ERROR_FAILED, "Canceled Recognize."));
                } else {
                    pendingRequests.resolveWithFailure(req, createErrorObject(RECO_ERROR_FAILED, "Unknown Action."));
                }
            } catch (Exception e){
                e.printStackTrace();
            }
        }
    }
}
