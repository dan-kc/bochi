package com.tofustash.app

import android.app.Application
import com.tofustash.app.data.repository.AuthRepository
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltAndroidApp
class TofustashApplication : Application() {
    @Inject lateinit var authRepository: AuthRepository

    override fun onCreate() {
        super.onCreate()
        CoroutineScope(Dispatchers.IO).launch { authRepository.initialize() }
    }
}
