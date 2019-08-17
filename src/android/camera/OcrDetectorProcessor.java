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

import com.creative.informatics.ui.GraphicOverlay;

import android.annotation.TargetApi;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Rect;
import android.os.Build;
import android.support.v4.content.LocalBroadcastManager;
import android.text.TextUtils;
import android.util.Log;
import android.util.Pair;
import android.util.SparseArray;

import com.google.android.gms.vision.Detector;
import com.google.android.gms.vision.text.Text;
import com.google.android.gms.vision.text.TextBlock;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * A very simple Processor which receives detected TextBlocks and adds them to the overlay
 * as OcrGraphics.
 */
public class OcrDetectorProcessor implements Detector.Processor<TextBlock> {
    private static final String TAG = OcrDetectorProcessor.class.getSimpleName();

    private GraphicOverlay<OcrGraphic> mGraphicOverlay;
    private Context mContext;
    //private boolean[] block_f;
    private DetectionDictInfo[] mDictInfoList;
    private static JSONObject POSTAL_CODES;

    OcrDetectorProcessor(GraphicOverlay<OcrGraphic> ocrGraphicOverlay, Context context) {
        mGraphicOverlay = ocrGraphicOverlay;
        mContext = context;

        mDictInfoList = new DetectionDictInfo[OcrCaptureFragment.ocrDict.size()];
        for( int i=0; i<mDictInfoList.length; i++){
            mDictInfoList[i] = new DetectionDictInfo();
            mDictInfoList[i].dict = OcrCaptureFragment.ocrDict.get(i);
        }

        initPostalCode();
    }

    /**
     * Called by the detector to deliver detection results.
     * If your application called for it, this could be a place to check for
     * equivalent detections by tracking TextBlocks that are similar in location and content from
     * previous frames, or reduce noise by eliminating TextBlocks that have not persisted through
     * multiple detections.
     */
    @TargetApi(Build.VERSION_CODES.KITKAT)
    @Override
    public void receiveDetections(Detector.Detections<TextBlock> detections) {
        mGraphicOverlay.clear();
        final SparseArray<TextBlock> items = detections.getDetectedItems();
        for( DetectionDictInfo item : mDictInfoList ){

            item.bSelected = false;
            item.mValueText = null;
            item.mKeywordBlock = null;
            item.mIndexInKeyBlock = -1;
        }
        //Log.e(TAG, "receiveDetections: 1 >>"+items.size());

        find_keyword(items);
        find_value(items);
        Set<OcrGraphic> graphics = new HashSet<OcrGraphic>();

        if ( OcrCaptureFragment.isDebug ) {
            for (int i = 0; i < items.size(); ++i) {
                TextBlock item = items.valueAt(i);
                OcrGraphic graphic = new OcrGraphic(mGraphicOverlay, item, Color.YELLOW);

                graphics.add(graphic);
            }
        }

        boolean isUpdatedValue = false;
        for( DetectionDictInfo info : mDictInfoList){
            if( info.mKeywordBlock != null){
                OcrGraphic graphic;

                int color = Color.GREEN;
                if( info.bSelected ) {
                    color = Color.RED;
                    isUpdatedValue = true;
                }

                if( info.mValueText != null ) {
                    graphic = new OcrGraphic(mGraphicOverlay, info.mValueText, color);
                    graphics.add(graphic);
                }

                if( info.mIndexInKeyBlock >= 0) {
                    Text keywordText = info.mKeywordBlock.getComponents().get(info.mIndexInKeyBlock);
                    graphic = new OcrGraphic(mGraphicOverlay, keywordText, color);
                    graphics.add(graphic);
                }
            }
        }
        if( isUpdatedValue ){
            JSONArray result = new JSONArray(new ArrayList<JSONObject>());
            for (OcrCaptureFragment.OCRDictionary dict : OcrCaptureFragment.ocrDict) {
                if (dict.resValue != null) {
                    try {
                        JSONObject objResult = new JSONObject();

                        objResult.putOpt("name", dict.name);
                        objResult.putOpt("value", dict.resValue);
                        result.put(objResult);
                    } catch (JSONException e) {
                        e.printStackTrace();
                    }
                }
            }

            if (result.length() > 0) {
                Intent intentData = new Intent(Capture1.ACTION_RECOGNIZED_ITEM);

                intentData.putExtra(Capture1.KEY_RESULT_DATA, result.toString());
                LocalBroadcastManager.getInstance(mContext).sendBroadcast(intentData);
            }
        }
        mGraphicOverlay.addAll(graphics);
    }

    private boolean checkServiceAddressEx(SparseArray<TextBlock>  blocks){
        for( DetectionDictInfo info : mDictInfoList) {
            if ( !info.dict.name.toLowerCase().contains("service address")) continue;

            // Service Address without keyword
            if( !info.dict.resKeyword.isEmpty() ) break;

            if (info.mIndexOfKey >= 0){
                info.dict.resValue = "";
                break;
            }
            if (info.mKeywordBlock != null) break;

            JSONArray postal = POSTAL_CODES.optJSONArray(OcrCaptureFragment.ocrCountry);
            if (postal != null) {
                for( int i=0; i<postal.length(); i++){
                    for (int j=0;j<blocks.size();j++) {
                        TextBlock block = blocks.valueAt(j);
                        for (Text item : block.getComponents()) {
                            Pattern p = Pattern.compile(postal.optString(i));
                            if (p.matcher(item.getValue()).find()) {
                                Text secAddrText = item;
                                String addressValue = secAddrText.getValue();
                                ArrayList<String> builder = new ArrayList<String>();

                                String test = secAddrText.getValue().replaceAll("[,.\\s]+", ",");
                                if( test.split(",").length < 5 ) {
                                    Text firstAddressText = null;
                                    for (int k=0;k<blocks.size();k++) {
                                        TextBlock ablock = blocks.valueAt(k);
                                        for (Text text : ablock.getComponents()) {
                                            if (secAddrText.getBoundingBox().top <= text.getBoundingBox().top)
                                                continue;

                                            if (firstAddressText == null)
                                                firstAddressText = text;
                                            else if (firstAddressText.getBoundingBox().top < text.getBoundingBox().top)
                                                firstAddressText = text;
                                        }
                                    }
                                    if( firstAddressText != null ){
                                        if (firstAddressText.getValue().matches("^[0-9,.$\\s]+$")) {
                                            Log.e(TAG, "checkServiceAddressEx: First address line is not matched:" + firstAddressText.getValue() );
                                        } else if (firstAddressText.getValue().matches("(?i:^[a-z0-9,.\\s]+$)")) {
                                            builder.add(firstAddressText.getValue());
                                        }
                                    }
                                }
                                builder.add(addressValue);
                                addressValue = TextUtils.join(", ", builder);

                                if( info.dict.checkMatchValuePattern(addressValue) != null) {
                                    info.mValueText = item;

                                    if (info.dict.setValueIfAcceptable(addressValue)) {
                                        info.bSelected = true;
                                        Log.d(TAG, "find_value_in_text: a new Value:" + info.dict.getDisplayString());
                                    }
                                    return true;
                                }
                                return false;
                            }
                        }
                    }
                }
            }

            return false;
        }
        return false;
    }
    private void find_keyword(SparseArray<TextBlock> blocks){

        for(int i=0; i<blocks.size(); i++){
            TextBlock item = blocks.valueAt(i);
            List<? extends Text> list = item.getComponents();
            for( int j=0; j<list.size(); j++){
                String text = list.get(j).getValue();
                for (DetectionDictInfo info : mDictInfoList) {
                    int inxKey = info.dict.getIndexKeywords(text);
                    if (inxKey > -1) {
                        info.mIndexOfKey = inxKey;
                        info.mKeywordBlock = item;
                        info.mIndexInKeyBlock = j;
                        //break;
                    }
                }
            }
        }
    }

    private void find_value(SparseArray<TextBlock> blocks) {

        if( checkServiceAddressEx(blocks) ) {
            Log.d(TAG, "find_keyword: Detected Service address from Country name");
            //block_f[i] = true;
        }
        for (DetectionDictInfo info : mDictInfoList) {
            if( info.mKeywordBlock!=null ){

                if( check_attribute(info) ) continue;

                if( find_value_in_text(info) ) continue;

                if( find_value_in_right(blocks, info) ) continue;

                if( find_value_in_below(blocks, info) ) continue;

                String key = info.dict.keywords.get(info.mIndexOfKey).first;
                String phonetic = info.dict.keywords.get(info.mIndexOfKey).second;
                Log.e(TAG, "find_value: no find value >> keyword : " + key
                        + ", phonetic: " + phonetic);

            }
        }

    }

    private boolean check_attribute(DetectionDictInfo info){
        if( !info.dict.attribute ) return false;
        if( info.mIndexInKeyBlock < 0 ) return false;

        Text keyword = info.mKeywordBlock.getComponents().get(info.mIndexInKeyBlock);

        String key = info.dict.keywords.get(info.mIndexOfKey).first;
        int offset = keyword.getValue().toLowerCase().indexOf(key.toLowerCase());
        if( offset < 0) return false;

        if( info.dict.setValueIfAcceptable(key) ) {
            info.bSelected = true;
            info.dict.resKeyword = key;
            Log.d(TAG, "check_attribute: A new Value:" + info.dict.getDisplayString());
        }
        return true;
    }

    private boolean find_value_in_text(DetectionDictInfo info){
        if( info.mIndexInKeyBlock < 0 ) return false;

        Text keyword = info.mKeywordBlock.getComponents().get(info.mIndexInKeyBlock);
        for(Pair<String, String> pair : info.dict.keywords){
            String key = pair.first;
            int offset = keyword.getValue().toLowerCase().indexOf(key.toLowerCase());
            if( offset < 0) continue;
            String value = keyword.getValue().substring(offset + key.length()).trim();

            if( info.dict.checkMatchValuePattern(value) != null) {
                info.mValueText = keyword;

                if (info.dict.setValueIfAcceptable(value)) {
                    info.bSelected = true;
                    info.dict.resKeyword = info.dict.keywords.get(info.mIndexOfKey).first;
                    Log.d(TAG, "find_value_in_text: A new Value:" + info.dict.getDisplayString());
                }
                return true;
            }
        }

        return false;
    }

    private boolean find_value_in_right(SparseArray<TextBlock> blocks, DetectionDictInfo info){
        if( info.mIndexInKeyBlock < 0 ) return false;

        Text keyword = info.mKeywordBlock.getComponents().get(info.mIndexInKeyBlock);
        Rect rcKeyword = new Rect(keyword.getBoundingBox());
        ArrayList<Text> result = new ArrayList<Text>();
        for (int i=0;i<blocks.size();i++) {
            TextBlock block = blocks.valueAt(i);
            for( Text text : block.getComponents()){
                Rect rcText = new Rect(text.getBoundingBox());
                if( Math.abs(rcText.top-rcKeyword.top) > 10 ) continue;
                if( rcKeyword.right > rcText.left) continue;

                result.add(text);
            }
        }

        if( result.isEmpty() ) return false;

        Collections.sort(result, new Comparator<Text>() {
            @Override
            public int compare(Text o1, Text o2) {
                return o1.getBoundingBox().left - o2.getBoundingBox().left;
            }
        });

        Text text = result.get(0);
        if( info.dict.checkMatchValuePattern(text.getValue()) != null) {
            info.mValueText = text;
            if( info.mIndexOfKey < 0) info.dict.resValue="";

            if (info.dict.setValueIfAcceptable(text.getValue())) {
                info.bSelected = true;
                info.dict.resKeyword = info.dict.keywords.get(info.mIndexOfKey).first;
                Log.d(TAG, "find_value_in_right: " + info.dict.getDisplayString());
            }
            return true;
        }
        return false;
    }

    private boolean find_value_in_below(SparseArray<TextBlock> blocks, DetectionDictInfo info){
        if( info.mIndexInKeyBlock < 0 ) return false;
        if( !info.dict.hasPatterns() ) return false;

        Text keyword = info.mKeywordBlock.getComponents().get(info.mIndexInKeyBlock);
        Rect rcKeyword = new Rect(keyword.getBoundingBox());
        ArrayList<Text> result = new ArrayList<Text>();
        List<? extends Text> components = info.mKeywordBlock.getComponents();

        for( Text text : components){
            Rect rcText = text.getBoundingBox();
            if( (rcKeyword.bottom-10) > rcText.top || rcKeyword.left > rcText.right) continue;

            Rect union = new Rect(rcKeyword);
            union.union(rcText);
            Boolean best = true;
            for(Text item : components){
                if( item == text || item == keyword) continue;
                if( Rect.intersects(union, item.getBoundingBox())) {
                    best = false;
                    break;
                }
            }
            if( best ){
                result.add(text);
                break;
            }
        }

        if( result.isEmpty() ) {
            ArrayList<Text> allText = new ArrayList<Text>();
            for (int i=0; i<blocks.size(); i++) {
                TextBlock block = blocks.valueAt(i);
                allText.addAll(block.getComponents());
            }

            for( Text text : allText){
                Rect rcText = text.getBoundingBox();
                if( (rcKeyword.bottom-10) > rcText.top || rcKeyword.left > rcText.right) continue;

                Rect union = new Rect(rcKeyword);
                union.union(rcText);
                Boolean best = true;
                for(Text item : allText){
                    if( item == text || item == keyword) continue;
                    if( Rect.intersects(union, item.getBoundingBox())) {
                        best = false;
                        break;
                    }
                }
                if( best ){
                    result.add(text);
                    break;
                }
            }
        }

        if( result.isEmpty() ) return false;

        Text text = result.get(0);
        if( info.dict.checkMatchValuePattern(text.getValue()) != null) {
            info.mValueText = text;
            if( info.mIndexOfKey < 0) info.dict.resValue="";

            if (info.dict.setValueIfAcceptable(text.getValue())) {
                info.bSelected = true;
                info.dict.resKeyword = info.dict.keywords.get(info.mIndexOfKey).first;
                Log.d(TAG, "find_value_in_below: " + info.dict.getDisplayString());
            }
            return true;
        }
        return false;
    }

    /**
     * Frees the resources associated with this detection processor.
     */
    @Override
    public void release() {
        mGraphicOverlay.clear();
    }

    public class DetectionDictInfo {
        public OcrCaptureFragment.OCRDictionary dict;

        private boolean bSelected;

        private int mHeightRate;

        private int mIndexOfKey;

        private TextBlock mKeywordBlock;
        private int mIndexInKeyBlock;

        private Text mValueText;

        public DetectionDictInfo(){
            dict = null;
            bSelected = false;
            mHeightRate = 0;
            mIndexOfKey = -1;
            mKeywordBlock = null;
            mValueText = null;
            mIndexInKeyBlock = -1;
        }
    }

    private static void initPostalCode(){

        POSTAL_CODES = new JSONObject();
        JSONArray australia = new JSONArray();
        australia.put("VIC[\\s]*[0-9]{4}$");
        australia.put("NSW[\\s]*[0-9]{4}$");
        australia.put("QLD[\\s]*[0-9]{4}$");
        australia.put("NT[\\s]*[0-9]{4}$");
        australia.put("WA[\\s]*[0-9]{4}$");
        australia.put("SA[\\s]*[0-9]{4}$");
        australia.put("TAS[\\s]*[0-9]{4}$");

        try {
            POSTAL_CODES.putOpt("Australia", australia);
        } catch (JSONException e) {
            e.printStackTrace();
        }

    }
}
