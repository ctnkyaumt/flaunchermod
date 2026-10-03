/*
 * FLaunchermod
 * originally by efesser (30 May 2021)
 * ctnkyaumt 2026
 * Copyright (C) 2021 Étienne Fesser
 * Copyright (C) 2026 ctnkyaumt
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

package me.efesser.flauncher

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Build
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.WindowManager
import android.view.ContextThemeWrapper
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel

/** A real Android editor keeps remote navigation in the installed TV keyboard. */
class SystemTextInputDialog(private val activity: Activity) {
    private class Pending(
        val dialog: AlertDialog,
        val input: EditText,
        val result: MethodChannel.Result,
    )

    private var pending: Pending? = null

    fun show(arguments: Map<*, *>, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A text editor is already active", null)
            return
        }
        if (activity.isFinishing || activity.isDestroyed) {
            result.success(null)
            return
        }
        val title = arguments["title"] as String
        val initialValue = arguments["initialValue"] as String
        val fieldLabel = arguments["fieldLabel"] as String
        val action = arguments["action"] as String
        require(action == "search" || action == "done") { "Unsupported editor action" }
        val submitLabel = arguments["submitLabel"] as String
        val allowEmpty = arguments["allowEmpty"] as Boolean
        val colors = arguments["colors"] as Map<*, *>
        fun color(name: String) = (colors[name] as Number).toInt()
        val foreground = color("foreground")
        val secondary = color("secondary")
        val dialogContext = ContextThemeWrapper(activity, R.style.SystemTextInputDialogTheme)
        val actionId = if (action == "search") EditorInfo.IME_ACTION_SEARCH else EditorInfo.IME_ACTION_DONE
        val input = object : EditText(dialogContext) {
            override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
                super.onWindowFocusChanged(hasWindowFocus)
                if (hasWindowFocus) post { showKeyboard(this) }
            }
        }.apply {
            inputType = InputType.TYPE_CLASS_TEXT
            setSingleLine(true)
            imeOptions = actionId or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            hint = fieldLabel
            setText(initialValue)
            setSelection(text.length)
            isFocusableInTouchMode = true
            setTextColor(foreground)
            setHintTextColor(secondary)
            highlightColor = color("selection")
            backgroundTintList = ColorStateList(
                arrayOf(intArrayOf(android.R.attr.state_focused), intArrayOf()),
                intArrayOf(foreground, secondary),
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                textCursorDrawable = textCursorDrawable?.mutate()?.apply { setTint(color("cursor")) }
            }
        }
        val padding = (24 * activity.resources.displayMetrics.density).toInt()
        val content = LinearLayout(dialogContext).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding / 2, padding, 0)
            addView(TextView(dialogContext).apply {
                text = fieldLabel
                setTextColor(foreground)
            })
            addView(input, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
        }
        val dialog = AlertDialog.Builder(dialogContext)
            .setCustomTitle(TextView(dialogContext).apply {
                text = title
                textSize = 20f
                setTextColor(foreground)
                setPadding(padding, padding, padding, padding / 2)
            })
            .setView(content)
            .setNegativeButton("CANCEL", null)
            .setPositiveButton(submitLabel, null)
            .create()
        val entry = Pending(dialog, input, result)
        pending = entry

        fun submit() {
            val value = input.text.toString().trim()
            if (allowEmpty || value.isNotEmpty()) finish(entry, value)
        }
        input.setOnEditorActionListener { _, editorAction, keyEvent ->
            // Only an explicit IME action submits. An unmatched opening OK/Enter
            // release is a hardware KeyEvent and must not accept the dialog.
            if (keyEvent == null && editorAction == actionId) {
                submit()
                true
            } else {
                false
            }
        }
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                dialog.getButton(AlertDialog.BUTTON_POSITIVE)?.isEnabled =
                    allowEmpty || input.text.toString().trim().isNotEmpty()
            }
            override fun afterTextChanged(s: Editable?) {}
        })
        dialog.setOnDismissListener { finish(entry, null) }
        dialog.setOnShowListener {
            dialog.window?.setBackgroundDrawable(GradientDrawable().apply {
                setColor(color("background"))
                cornerRadius = 4 * activity.resources.displayMetrics.density
            })
            val buttonText = ColorStateList(
                arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf()),
                intArrayOf(secondary, foreground),
            )
            for (buttonId in listOf(AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_POSITIVE)) {
                dialog.getButton(buttonId).apply {
                    setTextColor(buttonText)
                    // Match Flutter's button overlay while retaining native
                    // focus/activation, so D-pad navigation stays with the IME.
                    background = StateListDrawable().apply {
                        addState(intArrayOf(android.R.attr.state_focused), ColorDrawable(color("focus")))
                        addState(intArrayOf(android.R.attr.state_pressed), ColorDrawable(color("focus")))
                        addState(intArrayOf(), ColorDrawable(Color.TRANSPARENT))
                    }
                }
            }
            dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener { finish(entry, null) }
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).apply {
                isEnabled = allowEmpty || input.text.toString().trim().isNotEmpty()
                setOnClickListener { submit() }
            }
            input.requestFocus()
            input.post { showKeyboard(input) }
        }
        dialog.window?.apply {
            clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        }
        try {
            dialog.show()
        } catch (error: Exception) {
            // Leave no callback behind if Android cannot attach the window.
            if (pending === entry) {
                pending = null
                dialog.setOnDismissListener(null)
                dialog.dismiss()
                result.error("native_error", error.message, null)
            }
        }
    }

    private fun showKeyboard(input: EditText) {
        val entry = pending ?: return
        if (entry.input !== input || !entry.dialog.isShowing ||
            !input.hasFocus() || !input.hasWindowFocus()) return
        val keyboard = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        keyboard.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun finish(entry: Pending, value: String?) {
        if (pending !== entry) return
        pending = null // Dismiss, lifecycle and IME callbacks can finish only once.
        try {
            val keyboard = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            keyboard.hideSoftInputFromWindow(entry.input.windowToken, 0)
        } finally {
            try {
                entry.dialog.dismiss()
            } finally {
                entry.result.success(value)
            }
        }
    }

    fun cancel() {
        pending?.let { finish(it, null) }
    }
}
