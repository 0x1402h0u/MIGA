package com.android.ampulos

import android.content.Context

object PredictiveBackPreferences {
    private const val PREF_NAME = "predictive_back_prefs"
    private const val KEY_TRANSPARENT = "back_gesture_transparent"
    private const val KEY_FLOATING_BAR = "floating_bar_enabled"
    private const val KEY_BAR_SIZE = "bar_size"
    private const val KEY_MODERN_STYLE = "modern_style"
    private const val KEY_UI_MODE = "ui_mode"

    fun isTransparentEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_TRANSPARENT, true)
    }

    fun setTransparentEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_TRANSPARENT, enabled)
            .apply()
    }

    fun isFloatingBarEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_FLOATING_BAR, true)
    }

    fun setFloatingBarEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_FLOATING_BAR, enabled)
            .apply()
    }

    fun getBarSize(context: Context): String {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getString(KEY_BAR_SIZE, "中") ?: "中"
    }

    fun setBarSize(context: Context, size: String) {
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_BAR_SIZE, size)
            .apply()
    }

    fun isModernStyleEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_MODERN_STYLE, false)
    }

    fun setModernStyleEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_MODERN_STYLE, enabled)
            .apply()
    }

    fun isMiuixModeEnabled(context: Context): Boolean {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_UI_MODE, false)
    }

    fun setMiuixModeEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_UI_MODE, enabled)
            .apply()
    }
}
