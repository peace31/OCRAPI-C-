package com.creative.informatics.camera;

import java.util.ArrayList;
import java.util.List;

import de.zedlitz.phonet4java.Coder;
import de.zedlitz.phonet4java.DaitchMokotoff;
import de.zedlitz.phonet4java.KoelnerPhonetik;
import de.zedlitz.phonet4java.Phonet1;
import de.zedlitz.phonet4java.Phonet2;
import de.zedlitz.phonet4java.Soundex;
import de.zedlitz.phonet4java.SoundexRefined;

public class MetaEngineController {
    Coder mCoder = null;

    MetaEngineController(String id){
        initWithEngineId(id);
    }

    private void initWithEngineId(String id){
        List<Coder> list = new ArrayList<>();
        list.add(new DaitchMokotoff());
        list.add(new KoelnerPhonetik());
        list.add(new Phonet1());
        list.add(new Phonet2());
        list.add(new Soundex());
        list.add(new SoundexRefined());

        for(Coder item : list){
            if( item.getEngineId().equalsIgnoreCase(id) ){
                mCoder = item;
                break;
            }
        }
    }

    public String getSelectedEngineId(){
        if( mCoder != null) return mCoder.getEngineId();

        return "native";
    }

    public String getPhoneticText(String text){
        if( mCoder == null ) return text;

        return mCoder.code(text);
    }


}
