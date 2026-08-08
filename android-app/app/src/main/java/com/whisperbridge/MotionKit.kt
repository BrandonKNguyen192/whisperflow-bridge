package com.whisperbridge

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ArgbEvaluator
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.animation.Interpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import androidx.core.view.animation.PathInterpolatorCompat

/**
 * Material 3 motion tokens, transcribed from
 * https://m3.material.io/styles/motion/overview
 *
 * The idea is small durations + emphasized easing so UI feels alive without
 * dragging. Three duration buckets (short / medium / long) cover the common
 * micro-interactions in this app -- chip swap, button press, card reveal,
 * status pulse, dialog appear. No custom script needed; push an animator set
 * through the helpers below and the ease handles the rest.
 */
object MotionKit {

    // -- Duration tokens (ms) --------------------------------------
    // M3 short1/2/3/4 -> 50/100/150/200, medium1/2/3/4 -> 250/300/350/400,
    // long1..4 -> 450/500/550/600. We use the rounded center of each band.
    const val DUR_SHORT_2 = 100L
    const val DUR_SHORT_4 = 200L
    const val DUR_MEDIUM_2 = 300L
    const val DUR_LONG_2 = 500L

    // -- Easing curves ---------------------------------------------
    // see: m3.material.io/styles/motion/easing
    // Emphasized (standard)   cubic-bezier(0.2, 0, 0, 1)
    // EmphasizedDecel         cubic-bezier(0.05, 0.7, 0.1, 1)   arrivals
    // EmphasizedAccel         cubic-bezier(0.3, 0, 0.8, 0.15)   departures
    private val STANDARD: Interpolator = PathInterpolatorCompat.create(0.2f, 0f, 0f, 1f)
    private val DECEL: Interpolator = PathInterpolatorCompat.create(0.05f, 0.7f, 0.1f, 1f)
    private val ACCEL: Interpolator = PathInterpolatorCompat.create(0.3f, 0f, 0.8f, 0.15f)
    val LINEAR: Interpolator = LinearInterpolator()

    // Material Expressive leans on spring physics. OvershootInterpolator is
    // the zero-dependency way to get that bouncy spring on the view system.
    private val SPRING_SOFT = OvershootInterpolator(1.2f)
    private val SPRING_BOUNCY = OvershootInterpolator(2.4f)

    /** Card fades in and rises to rest -- used on activity appearance. */
    fun revealRise(view: View, startDelay: Long = 0L) {
        view.alpha = 0f
        view.translationY = 24f * view.resources.displayMetrics.density
        view.animate()
            .alpha(1f)
            .translationY(0f)
            .setDuration(DUR_MEDIUM_2)
            .setInterpolator(STANDARD)
            .setStartDelay(startDelay)
            .withLayer()
            .start()
    }

    /** Press-down: instant dip, then spring back to identity. Soft on failure. */
    fun pressPulse(view: View, ok: Boolean = true) {
        val dip = 0.94f
        val peak = if (ok) 1.04f else 1.0f

        val downX = ObjectAnimator.ofFloat(view, View.SCALE_X, 1f, dip).apply {
            duration = DUR_SHORT_2; interpolator = ACCEL
        }
        val downY = ObjectAnimator.ofFloat(view, View.SCALE_Y, 1f, dip).apply {
            duration = DUR_SHORT_2; interpolator = ACCEL
        }
        val upX = ObjectAnimator.ofFloat(view, View.SCALE_X, dip, peak, 1f).apply {
            duration = DUR_SHORT_4; interpolator = DECEL
        }
        val upY = ObjectAnimator.ofFloat(view, View.SCALE_Y, dip, peak, 1f).apply {
            duration = DUR_SHORT_4; interpolator = DECEL
        }

        val down = AnimatorSet().apply { playTogether(downX, downY) }
        val up = AnimatorSet().apply { playTogether(upX, upY) }
        val set = AnimatorSet().apply { playSequentially(down, up) }
        set.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationStart(animation: Animator) {
                view.setLayerType(View.LAYER_TYPE_HARDWARE, null)
            }

            override fun onAnimationEnd(animation: Animator) {
                view.setLayerType(View.LAYER_TYPE_NONE, null)
                view.scaleX = 1f
                view.scaleY = 1f
            }
        })
        set.start()
    }

    /**
     * Crossfade between two color ints. Caller passes a mutator lambda
     * that actually applies the interpolated color so we don't tie this
     * helper to any particular view type.
     */
    fun crossfadeColor(
        from: Int,
        to: Int,
        apply: (Int) -> Unit,
        duration: Long = DUR_MEDIUM_2
    ) {
        ValueAnimator.ofObject(ArgbEvaluator(), from, to).apply {
            this.duration = duration
            this.interpolator = STANDARD
            addUpdateListener { a -> apply(a.animatedValue as Int) }
        }.start()
    }

    /** A soft infinite pulse -- used by the status dot when not connected. */
    private var statusPulse: Animator? = null
    fun startBreath(view: View) {
        stopBreath()
        val a = ObjectAnimator.ofFloat(view, View.ALPHA, 1f, 0.35f).apply {
            duration = 1400L
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = LINEAR
        }
        a.start()
        statusPulse = a
    }

    fun stopBreath() {
        statusPulse?.cancel()
        statusPulse = null
    }

    fun setBreathing(view: View, on: Boolean) {
        if (on) startBreath(view) else {
            stopBreath()
            view.animate().cancel()
            view.alpha = 1f
        }
    }

    /** Snap a view down slightly for tactile feedback. */
    fun tapIn(view: View) {
        view.animate()
            .scaleX(0.97f)
            .scaleY(0.97f)
            .setDuration(60L)
            .setInterpolator(ACCEL)
            .withLayer()
            .start()
    }

    /** Fade a view out on the alpha axis; reverse of [revealRise]. */
    fun fadeOut(view: View, onEnd: (() -> Unit)? = null, duration: Long = DUR_SHORT_4) {
        view.animate()
            .alpha(0f)
            .setDuration(duration)
            .setInterpolator(ACCEL)
            .withLayer()
            .withEndAction {
                view.alpha = 1f
                onEnd?.invoke()
            }
            .start()
    }

    /** Staggered fade-in for chips, text rows, or any sequential list. */
    fun staggerIn(views: List<View>, perChild: Long = 40L) {
        views.forEachIndexed { i, v ->
            revealRise(v, startDelay = 40L + i * perChild)
        }
    }

    // -- Expressive spring helpers -----------------------------------

    /**
     * Scale-pop a view with a soft overshoot -- chip selection, checkmarks,
     * save confirmations. Reads as a spring, costs one animator.
     */
    fun pop(view: View, bouncy: Boolean = false) {
        view.animate().cancel()
        view.scaleX = 0.82f
        view.scaleY = 0.82f
        view.animate()
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(DUR_MEDIUM_2)
            .setInterpolator(if (bouncy) SPRING_BOUNCY else SPRING_SOFT)
            .withLayer()
            .start()
    }

    /**
     * Expressive press physics: dip on touch-down, spring back with overshoot
     * on release. Install as an OnTouchListener that returns false so the
     * normal click/ripple pipeline still runs.
     */
    fun installSpringPress(view: View, dipScale: Float = 0.94f) {
        view.setOnTouchListener { v, ev ->
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    v.animate().cancel()
                    v.animate()
                        .scaleX(dipScale)
                        .scaleY(dipScale)
                        .setDuration(DUR_SHORT_2)
                        .setInterpolator(ACCEL)
                        .withLayer()
                        .start()
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.animate().cancel()
                    v.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(DUR_MEDIUM_2)
                        .setInterpolator(SPRING_SOFT)
                        .withLayer()
                        .start()
                }
            }
            false
        }
    }

    /** Recursively install [installSpringPress] on every button in the tree. */
    fun installSpringPressRecursive(root: View) {
        if (root is android.widget.Button || root is android.widget.ImageButton) {
            installSpringPress(root)
        }
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                installSpringPressRecursive(root.getChildAt(i))
            }
        }
    }

    /** Quick celebratory pulse: scale up then settle, one beat. */
    fun successPulse(view: View) {
        val up = ObjectAnimator.ofFloat(view, View.SCALE_X, 1f, 1.12f).apply {
            duration = DUR_SHORT_2; interpolator = DECEL
        }
        val upY = ObjectAnimator.ofFloat(view, View.SCALE_Y, 1f, 1.12f).apply {
            duration = DUR_SHORT_2; interpolator = DECEL
        }
        val down = ObjectAnimator.ofFloat(view, View.SCALE_X, 1.12f, 1f).apply {
            duration = DUR_MEDIUM_2; interpolator = SPRING_SOFT
        }
        val downY = ObjectAnimator.ofFloat(view, View.SCALE_Y, 1.12f, 1f).apply {
            duration = DUR_MEDIUM_2; interpolator = SPRING_SOFT
        }
        AnimatorSet().apply {
            playSequentially(
                AnimatorSet().apply { playTogether(up, upY) },
                AnimatorSet().apply { playTogether(down, downY) }
            )
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    view.scaleX = 1f
                    view.scaleY = 1f
                }
            })
            start()
        }
    }

    /** Grow a horizontal accent line from its leading edge on first show. */
    fun growFromStart(view: View, startDelay: Long = 0L) {
        view.pivotX = 0f
        view.scaleX = 0f
        view.animate()
            .scaleX(1f)
            .setDuration(DUR_LONG_2)
            .setInterpolator(DECEL)
            .setStartDelay(startDelay)
            .withLayer()
            .start()
    }

    /** Crossfade-swap the text of a [android.widget.TextView]. */
    fun swapText(view: android.widget.TextView, newText: CharSequence) {
        view.animate().cancel()
        view.animate()
            .alpha(0f)
            .setDuration(DUR_SHORT_2)
            .setInterpolator(ACCEL)
            .withEndAction {
                view.text = newText
                view.animate()
                    .alpha(1f)
                    .setDuration(DUR_SHORT_2)
                    .setInterpolator(DECEL)
                    .start()
            }
            .start()
    }
}
