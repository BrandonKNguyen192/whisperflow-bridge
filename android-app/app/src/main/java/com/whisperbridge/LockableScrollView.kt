package com.whisperbridge

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import android.widget.ScrollView

/**
 * ScrollView that can pin its scrolling off while the phone trackpad is in
 * use, so moving the cursor never drags the page underneath it.
 */
class LockableScrollView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : ScrollView(context, attrs) {

    var scrollLocked: Boolean = false

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        if (scrollLocked) return false
        return super.onInterceptTouchEvent(ev)
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (scrollLocked) return false
        return super.onTouchEvent(ev)
    }
}
