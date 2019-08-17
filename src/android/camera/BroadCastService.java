package com.creative.informatics.camera;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;


public class BroadCastService extends BroadcastReceiver {

    public interface DetectResultCallbackInterface {

        void onDetectResult(int requestCode, Intent intent);

    }

    public Intent _intent;
    public DetectResultCallbackInterface _callBack;
    public int _requestCode;

    public BroadCastService(int requestCode) {
        super();
        _requestCode = requestCode;
    }

    public void setCallBack(DetectResultCallbackInterface callBack){
        _callBack = callBack;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        _intent = intent;
        if (_callBack != null)
            _callBack.onDetectResult(_requestCode, _intent);
    }
}
