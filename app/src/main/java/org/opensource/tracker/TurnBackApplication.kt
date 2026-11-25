package org.opensource.tracker

import android.app.Application
import android.content.Context
import org.osmdroid.config.Configuration

class TurnBackApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Order matters: load() restores persisted prefs and can replace the user agent, and OSM tile
        // servers reject requests with a default agent (blank grey tiles). Always set the agent last.
        val config = Configuration.getInstance()
        config.load(this, getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
        config.userAgentValue = packageName
    }
}
