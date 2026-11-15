package org.opensource.tracker

import android.app.Application
import org.osmdroid.config.Configuration

class TurnBackApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Configuration.getInstance().userAgentValue = packageName
    }
}
