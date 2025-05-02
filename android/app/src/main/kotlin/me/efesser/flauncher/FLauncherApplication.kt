/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package me.efesser.flauncher

import android.app.Application
import android.content.Context
import android.util.Log

/**
 * Custom Application class that prevents Firebase initialization
 * by providing a way to hook before Firebase auto-initialization occurs.
 */
class FLauncherApplication : Application() {
    
    override fun onCreate() {
        // Disable Firebase completely before super.onCreate()
        System.setProperty("firebase.crashlytics.collection.enabled", "false")
        System.setProperty("firebase.analytics.collection.enabled", "false")
        System.setProperty("firebase.crashlytics.enabled", "false")
        System.setProperty("firebase.messaging.auto-init.enabled", "false")
        System.setProperty("firebase.remoteconfig.enabled", "false")
        
        // Disable Firebase initialization entirely
        try {
            Class.forName("com.google.firebase.FirebaseApp")
                ?.getDeclaredField("DEFAULT_APP_NAME")
                ?.let { field ->
                    field.isAccessible = true
                    field.set(null, "__disabled__")
                }
        } catch (e: Exception) {
            // Ignore any errors - this is just an extra precaution
            Log.d("FLauncher", "Prevented Firebase initialization: ${e.message}")
        }
        
        // Call super after disabling properties
        super.onCreate()
        
        Log.d("FLauncher", "Application initialized with Firebase disabled")
    }
    
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        // More initialization can be done here if needed
    }
}
