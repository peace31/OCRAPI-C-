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
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.util.Log;

import com.google.android.gms.vision.text.Text;
import com.google.android.gms.vision.text.TextBlock;

import java.util.List;

/**
 * Graphic instance for rendering TextBlock position, size, and ID within an associated graphic
 * overlay view.
 */
public class OcrGraphic extends GraphicOverlay.Graphic {

    private int mId;

    private Paint sRectPaint;
    private Paint sTextPaint;
    private int sColor;
    private final TextBlock mTextBlock;
    private final Text mText;
    private RectF rect = new RectF();

    OcrGraphic(GraphicOverlay overlay, TextBlock text_block, int color) {
        this(overlay, text_block, null, color);
    }

    OcrGraphic(GraphicOverlay overlay, Text text, int color) {
        this(overlay, null, text, color);
    }

    OcrGraphic(GraphicOverlay overlay, TextBlock text_block, Text text, int color) {
        super(overlay);

        mTextBlock = text_block;
        mText = text;
        sColor = color;

        if (sRectPaint == null) {
            sRectPaint = new Paint();
            sRectPaint.setColor(sColor);
            sRectPaint.setStyle(Paint.Style.STROKE);
            sRectPaint.setStrokeWidth(2.0f);
        }

        if (sTextPaint == null) {
            sTextPaint = new Paint();
            sTextPaint.setColor(sColor);
            sTextPaint.setTextSize(50.0f);
            sTextPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        }

        rect = new RectF();
        // Redraw the overlay, as this graphic has been added.
        postInvalidate();
    }

    public int getId() {
        return mId;
    }

    public void setId(int id) {
        this.mId = id;
    }

    public TextBlock getTextBlock() {
        return mTextBlock;
    }

    /**
     * Checks whether a point is within the bounding box of this graphic.
     * The provided point should be relative to this graphic's containing overlay.
     * @param x An x parameter in the relative context of the canvas.
     * @param y A y parameter in the relative context of the canvas.
     * @return True if the provided point is contained within this graphic's bounding box.
     */
    public boolean contains(float x, float y) {
        TextBlock text = mTextBlock;
        if (text == null) {
            return false;
        }
        RectF rect = new RectF(text.getBoundingBox());
        rect.left = translateX(rect.left);
        rect.top = translateY(rect.top);
        rect.right = translateX(rect.right);
        rect.bottom = translateY(rect.bottom);
        return (rect.left < x && rect.right > x && rect.top < y && rect.bottom > y);
    }

    /**
     * Draws the text block annotations for position, size, and raw value on the supplied canvas.
     */
    @Override
    public void draw(Canvas canvas) {
        if (mTextBlock==null && mText==null)  return;

        TextBlock text_block = mTextBlock;
        boolean flag=false;
        if( mTextBlock!=null) {
            // Break the text into multiple lines and draw each one according to its own bounding box.
            List<? extends Text> textComponents = text_block.getComponents();
            for (Text currentText : textComponents) {
                float left = translateX(currentText.getBoundingBox().left);
                float right = translateX(currentText.getBoundingBox().right);
                float bottom = translateY(currentText.getBoundingBox().bottom);
                String block_text = currentText.getValue();
                //Log.d("Descriptor", String.valueOf(block_text));
                flag = true;
                setTextSizeForWidth(sTextPaint, right-left, block_text);
                canvas.drawText(currentText.getValue(), left, bottom, sTextPaint);
            }
        }

        Text text = mText;
        if( mText!=null){
            Rect rc = text.getBoundingBox();
            float left      = translateX(rc.left);
            float right      = translateX(rc.right);
            float bottom    = translateY(rc.bottom);
            setTextSizeForWidth(sTextPaint, right-left, text.getValue());
            canvas.drawText(text.getValue(), left, bottom, sTextPaint);

            // Draws the bounding box around the TextBlock.
            rect.left   = translateX(rc.left);
            rect.top    = translateY(rc.top);
            rect.right  = translateX(rc.right);
            rect.bottom = translateY(rc.bottom);
            canvas.drawRect(rect, sRectPaint);
        }

        if(flag)
        {
            Rect rc = text_block.getBoundingBox();
            // Draws the bounding box around the TextBlock.
            rect.left   = translateX(rc.left);
            rect.top    = translateY(rc.top);
            rect.right  = translateX(rc.right);
            rect.bottom = translateY(rc.bottom);
            canvas.drawRect(rect, sRectPaint);
        }



    }

    /**
     * Sets the text size for a Paint object so a given string of text will be a
     * given width.
     *
     * @param paint
     *            the Paint to set the text size for
     * @param desiredWidth
     *            the desired width
     * @param text
     *            the text that should be that width
     */
    private static void setTextSizeForWidth(Paint paint, float desiredWidth,
                                            String text) {

        // Pick a reasonably large value for the test. Larger values produce
        // more accurate results, but may cause problems with hardware
        // acceleration. But there are workarounds for that, too; refer to
        // http://stackoverflow.com/questions/6253528/font-size-too-large-to-fit-in-cache
        final float testTextSize = 48f;

        // Get the bounds of the text, using our testTextSize.
        paint.setTextSize(testTextSize);
        Rect bounds = new Rect();
        paint.getTextBounds(text, 0, text.length(), bounds);

        // Calculate the desired size as a proportion of our testTextSize.
        float desiredTextSize = testTextSize * desiredWidth / bounds.width();

        // Set the paint for that size.
        paint.setTextSize(desiredTextSize);
    }
}
