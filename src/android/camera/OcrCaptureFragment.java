/*
 * Copyright (C) The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.creative.informatics.camera;

import android.Manifest;
import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.app.Fragment;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.hardware.Camera;
import android.os.Bundle;
import android.support.annotation.NonNull;
import android.support.annotation.Nullable;
import android.support.v4.app.ActivityCompat;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.Pair;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import android.widget.Toast;

import com.creative.informatics.ui.CameraSource;
import com.creative.informatics.ui.CameraSourcePreview;
import com.creative.informatics.ui.GraphicOverlay;
import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.GoogleApiAvailability;
import com.google.android.gms.vision.text.TextRecognizer;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static java.lang.Math.max;
import static java.lang.Math.min;

/**
 * Activity for the multi-tracker app.  This app detects text and displays the value with the
 * rear facing camera. During detection overlay graphics are drawn to indicate the position,
 * size, and contents of each TextBlock.
 */
public final class OcrCaptureFragment extends Fragment {
    private static final String TAG = OcrCaptureFragment.class.getSimpleName();
    public static String[] resultStr = new String[8];
    public static final Object obj = new Object();
    // Intent request code to handle updating play services if needed.
    private static final int RC_HANDLE_GMS = 9001;

    // Permission request codes need to be < 256
    private static final int RC_HANDLE_CAMERA_PERM = 2;

    private CameraSource mCameraSource;
    private CameraSourcePreview mPreview;
    private GraphicOverlay<OcrGraphic> mGraphicOverlay;

    public static String ocrCountry;
    public static List<OCRDictionary> ocrDict;
    public static boolean isDebug;
    public static String metaEngineId;

    private View view;
    private Activity mActivity;
    private String mPackage;
    private MetaEngineController mMetaEngine = null;

    /**
     * Initializes the UI and creates the detector pipeline.
     */
    public void setOcrOptions(String strOption){
        // read parameters from the intent used to launch the activity.
        //boolean autoFocus = getIntent().getBooleanExtra(AutoFocus, false);
        //boolean useFlash = getIntent().getBooleanExtra(UseFlash, false);
        try {
            JSONObject ocrOption = new JSONObject(strOption);
            ocrCountry = ocrOption.optString("country");
            isDebug = ocrOption.optBoolean("debug");
            metaEngineId = ocrOption.optString("fieldMatchingMethodAndroid");
            if( metaEngineId.isEmpty() ) metaEngineId = "native";
            mMetaEngine = new MetaEngineController(metaEngineId);

            JSONArray ocrDictionary = ocrOption.optJSONArray("dictionary");
            ocrDict = new ArrayList<OCRDictionary>();
            for( int i=0; i<ocrDictionary.length(); i++ ){
                ocrDict.add(new OCRDictionary(mMetaEngine, ocrDictionary.getJSONObject(i)));
            }
            Log.d(TAG, "optCountry: " + ocrCountry);
            Log.d(TAG, "isDebug: " + isDebug);
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    @Nullable
    @Override
    public View onCreateView(LayoutInflater inflater, @Nullable ViewGroup container, Bundle savedInstanceState) {
        super.onCreateView(inflater, container, savedInstanceState);

        mActivity = getActivity();
        mPackage = getActivity().getPackageName();

        view = inflater.inflate(getResources().getIdentifier("ocr_capture", "layout", mPackage), container, false);

        mPreview = view.findViewById(getResources().getIdentifier("preview", "id", mPackage));
        mGraphicOverlay = view.findViewById(getResources().getIdentifier("graphicOverlay", "id", mPackage));

        TextView metaEngineId = view.findViewById(getResources().getIdentifier("meta_phonetic", "id", mPackage));
        if( mMetaEngine != null && metaEngineId != null) {
            metaEngineId.setText(mMetaEngine.getSelectedEngineId());
        }

        // Check for the camera permission before accessing the camera.  If the
        // permission is not granted yet, request permission.
        int rc = ActivityCompat.checkSelfPermission(mActivity, Manifest.permission.CAMERA);
        if (rc == PackageManager.PERMISSION_GRANTED) {
            createCameraSource(true, false);
        } else {
            requestCameraPermission();
        }

        return view;
    }

    /**
     * Handles the requesting of the camera permission.  This includes
     * showing a "Snackbar" message of why the permission is needed then
     * sending the request.
     */
    private void requestCameraPermission() {
        Log.w(TAG, "Camera permission is not granted. Requesting permission");

        final String[] permissions = new String[]{Manifest.permission.CAMERA};

        if (!ActivityCompat.shouldShowRequestPermissionRationale(mActivity,
                Manifest.permission.CAMERA)) {
            ActivityCompat.requestPermissions(mActivity, permissions, RC_HANDLE_CAMERA_PERM);
            return;
        }

        final Activity thisActivity = mActivity;

        View.OnClickListener listener = new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                ActivityCompat.requestPermissions(thisActivity, permissions,
                        RC_HANDLE_CAMERA_PERM);
            }
        };

        int idPermissionText = getResources().getIdentifier("permission_camera_rationale", "string", mPackage);
        Toast.makeText(mActivity, idPermissionText, Toast.LENGTH_SHORT)
                .show();
    }

    /**
     * Creates and starts the camera.  Note that this uses a higher resolution in comparison
     * to other detection examples to enable the ocr detector to detect small text samples
     * at long distances.
     *
     * Suppressing InlinedApi since there is a check that the minimum version is met before using
     * the constant.
     */
    @SuppressLint("InlinedApi")
    private void createCameraSource(boolean autoFocus, boolean useFlash) {
        Context context = mActivity.getApplicationContext();

        // A text recognizer is created to find text.  An associated processor instance
        // is set to receive the text recognition results and display graphics for each text block
        // on screen.
        TextRecognizer textRecognizer = new TextRecognizer.Builder(context).build();
        textRecognizer.setProcessor(new OcrDetectorProcessor(mGraphicOverlay, mActivity.getApplicationContext()));

        if (!textRecognizer.isOperational()) {
            // Note: The first time that an app using a Vision API is installed on a
            // device, GMS will download a native libraries to the device in order to do detection.
            // Usually this completes before the app is run for the first time.  But if that
            // download has not yet completed, then the above call will not detect any text,
            // barcodes, or faces.
            //
            // isOperational() can be used to check if the required native libraries are currently
            // available.  The detectors will automatically become operational once the library
            // downloads complete on device.
            Log.w(TAG, "Detector dependencies are not yet available.");

            // Check for low storage.  If there is low storage, the native library will not be
            // downloaded, so detection will not become operational.
            IntentFilter lowStorageFilter = new IntentFilter(Intent.ACTION_DEVICE_STORAGE_LOW);
            boolean hasLowStorage = mActivity.registerReceiver(null, lowStorageFilter) != null;

            if (hasLowStorage) {
                Toast.makeText(mActivity, getResources().getIdentifier("low_storage_error", "string", mPackage), Toast.LENGTH_LONG).show();
                Log.w(TAG, getString(getResources().getIdentifier("low_storage_error", "string", mPackage)));
            }
        }

        DisplayMetrics displayMetrics = new DisplayMetrics();
        mActivity.getWindowManager().getDefaultDisplay().getMetrics(displayMetrics);
        int width = displayMetrics.widthPixels;
        int height = displayMetrics.heightPixels;

        // Creates and starts the camera.  Note that this uses a higher resolution in comparison
        // to other detection examples to enable the text recognizer to detect small pieces of text.
        mCameraSource =
                new CameraSource.Builder(mActivity.getApplicationContext(), textRecognizer)
                .setFacing(CameraSource.CAMERA_FACING_BACK)
                .setRequestedPreviewSize(max(width, height), min(width, height))
                .setRequestedFps(2.0f)
                .setFlashMode(useFlash ? Camera.Parameters.FLASH_MODE_TORCH : null)
                .setFocusMode(autoFocus ? Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE : null)
                .build();
    }

    /**
     * Restarts the camera.
     */
    @Override
    public void onResume() {
        super.onResume();

        startCameraSource();
    }

    @Override
    public void onPause() {
        super.onPause();

        if (mPreview != null) {
            mPreview.stop();
        }
    }

    /**
     * Stops the camera.
     */


    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);

        if (mPreview != null) {
            mPreview.stop();
        }
        startCameraSource();
    }

    /**
     * Releases the resources associated with the camera source, the associated detectors, and the
     * rest of the processing pipeline.
     */
    @Override
    public void onDestroy() {
        if (mPreview != null) {
            mPreview.release();
        }

        super.onDestroy();
    }

    /**
     * Callback for the result from requesting permissions. This method
     * is invoked for every call on {@link #requestPermissions(String[], int)}.
     * <p>
     * <strong>Note:</strong> It is possible that the permissions request interaction
     * with the user is interrupted. In this case you will receive empty permissions
     * and results arrays which should be treated as a cancellation.
     * </p>
     *
     * @param requestCode  The request code passed in {@link #requestPermissions(String[], int)}.
     * @param permissions  The requested permissions. Never null.
     * @param grantResults The grant results for the corresponding permissions
     *                     which is either {@link PackageManager#PERMISSION_GRANTED}
     *                     or {@link PackageManager#PERMISSION_DENIED}. Never null.
     * @see #requestPermissions(String[], int)
     */
    @Override
    public void onRequestPermissionsResult(int requestCode,
                                           @NonNull String[] permissions,
                                           @NonNull int[] grantResults) {
        if (requestCode != RC_HANDLE_CAMERA_PERM) {
            Log.d(TAG, "Got unexpected permission result: " + requestCode);
            super.onRequestPermissionsResult(requestCode, permissions, grantResults);
            return;
        }

        if (grantResults.length != 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            Log.d(TAG, "Camera permission granted - initialize the camera source");
            // We have permission, so create the camerasource
            //boolean autoFocus = getIntent().getBooleanExtra(AutoFocus,false);
            //boolean useFlash = getIntent().getBooleanExtra(UseFlash, false);
            createCameraSource(true, false);
            return;
        }

        Log.e(TAG, "Permission not granted: results len = " + grantResults.length +
                " Result code = " + (grantResults.length > 0 ? grantResults[0] : "(empty)"));

        DialogInterface.OnClickListener listener = new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int id) {
                mActivity.finish();
            }
        };

        AlertDialog.Builder builder = new AlertDialog.Builder(mActivity);
        builder.setTitle("Multitracker sample")
                .setMessage(getResources().getIdentifier("no_camera_permission", "string", mPackage))
                .setPositiveButton(getResources().getIdentifier("ok", "string", mPackage), listener)
                .show();
    }

    /**
     * Starts or restarts the camera source, if it exists.  If the camera source doesn't exist yet
     * (e.g., because onResume was called before the camera source was created), this will be called
     * again when the camera source is created.
     */
    private void startCameraSource() throws SecurityException {
        // Check that the device has play services available.
        int code = GoogleApiAvailability.getInstance()
                .isGooglePlayServicesAvailable(mActivity.getApplicationContext());
        if (code != ConnectionResult.SUCCESS) {
            Dialog dlg =
                    GoogleApiAvailability.getInstance().getErrorDialog(mActivity, code, RC_HANDLE_GMS);
            dlg.show();
        }

        if (mCameraSource != null) {
            try {
                mPreview.start(mCameraSource, mGraphicOverlay);
            } catch (IOException e) {
                Log.e(TAG, "Unable to start camera source.", e);
                mCameraSource.release();
                mCameraSource = null;
            }
        }
    }


    public static class OCRDictionary {
        private static final String DEFAULT_VALUE = "---";

        public String name;
        public boolean mandatory;
        public List<Pair<String,String>> keywords;      // Keyword & PhoneticKeyword Pair
        public List<String> patterns;
        public boolean attribute;
        public String resKeyword;
        public String resValue;
        public int indexOfPattern;
        private MetaEngineController mMetaEngine;

        public OCRDictionary( MetaEngineController engine, JSONObject object){
            name = object.optString("Name");
            mandatory = object.optBoolean("Mandatory");
            keywords = new ArrayList<Pair<String,String>>();
            mMetaEngine = engine;

            JSONArray array = object.optJSONArray("Keywords");
            if( array != null) {
                for (int i = 0; i < array.length(); i++) {
                    String keyword = array.optString(i);
                    String phoneticKey = mMetaEngine.getPhoneticText(keyword);
                    keywords.add(Pair.create(keyword, phoneticKey));
                }
            }

            patterns = new ArrayList<String>();
            String strPatterns = object.optString("Patterns");
            if( !strPatterns.isEmpty() )
                patterns = Arrays.asList(strPatterns.split("&&"));
            else
                patterns = null;

            attribute = object.optBoolean("Attribute");

            resKeyword = "";
            resValue = "";
            indexOfPattern = -1;
        }

        public boolean hasPatterns(){
            return patterns!=null && patterns.size()>0;
        }

        private String getKeyName(){
            return resKeyword.isEmpty() ? name : resKeyword;
        }

        public String getDisplayValue() {
            return resValue.isEmpty() ? DEFAULT_VALUE : resValue;
        }

        public String getDisplayString(){
            String result = name + ":" + getDisplayValue();
            result += "/" + resKeyword + "/" + (indexOfPattern + 1);

            return result;
        }

        public boolean isSetValue(){
            return !resValue.isEmpty();
        }

        public int getIndexKeywords(String string){
            for(int i=0; i<keywords.size(); i++){
                if( attribute ) {
                    String key = keywords.get(i).first;
                    if( checkContainKeyword(key, string) )
                        return i;
                } else {
                    if (matchMetaPhonetic(keywords.get(i), string))
                        return i;
                }
            }
            return -1;
        }

        private boolean checkContainKeyword(String key, String container){
            String sKey = key.toLowerCase();
            String sContainer = container.toLowerCase();
            if( sContainer.contains(sKey) ){
                if( sKey.length() > 10 ) return true;

                Pattern p = Pattern.compile("[a-z0-9]"+sKey);
                if (p.matcher(container).find())
                    return false;

                p = Pattern.compile(sKey+"[a-z0-9]");
                if( p.matcher(container).find())
                    return false;

                return true;
            }

            return false;
        }

        private boolean matchMetaPhonetic(Pair<String, String> key, String container) {
            String phoneticKey = key.second;

            int wordCount = key.first.split(" ").length;
            String[] words = container.split("[ ]+");
            if( words.length < wordCount ) return false;

            List<String> list = new ArrayList<String>();
            for( int j=0; j<wordCount; j++){
                list.add(words[j]);
            }
            String limitedString = TextUtils.join(" ", list);
            String phoneticText = mMetaEngine.getPhoneticText(limitedString);

            if( phoneticText.equalsIgnoreCase(phoneticKey))
                return true;

            return false;
        }

        public Map<String, Object> checkMatchValuePattern(String string){
            if( string==null || string.isEmpty() ) return null;
            if( patterns == null) return null;

            final HashMap<String, Object> resultMap = new HashMap<String, Object>();
            String res = ""; int num = -1;
            boolean result = false;
            if( !hasPatterns() ){
                res = string;
                num = -1;
                result = true;
            } else {
                for (int i=0; i<patterns.size(); i++) {
                    String pattern = patterns.get(i);
                    Pattern p = Pattern.compile("(?i:"+pattern+")");
                    Matcher match = p.matcher(string);
                    if( match.find() ) {
                        String strMatched = match.group();
                        if( strMatched.length() > res.length() ){
                            res = strMatched;
                            num = i;
                            result = true;
                        }
                    }
                }
            }
            if( result ){
                resultMap.put("result_value", res);
                resultMap.put("pattern_num", num);
                return resultMap;
            }
            return null;
        }

        public boolean setValueIfAcceptable(String string){
            if( attribute ) {
                if( string!=null && !string.isEmpty() ) {
                    if (resValue.isEmpty()) {
                        resValue = string;
                        return true;
                    }
                }
                return false;
            }

            Map<String, Object> result = checkMatchValuePattern(string);
            if( result == null) return false;

            String value = (String)result.get("result_value");
            if(value==null) value = "";
            Integer num = (Integer) result.get("pattern_num");
            if(num==null) num = -1;

            if( isSetValue() ){
                if( value.length() > resValue.length() ){
                    resValue = value;
                    indexOfPattern = num;
                    return true;
                }
            } else {
                resValue = value;
                indexOfPattern = num;
                return true;
            }

            return false;
        }
    }
}
