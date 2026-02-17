package com.tofustash.app.data.remote

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.Request
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
@OptIn(ExperimentalCoroutinesApi::class)
class AuthInterceptorTest {

    private lateinit var server: MockWebServer
    private lateinit var tokenManager: TokenManager
    private lateinit var client: OkHttpClient
    private lateinit var dataStore: DataStore<Preferences>
    private val testScope = TestScope(UnconfinedTestDispatcher())

    @Before
    fun setup() {
        server = MockWebServer()
        server.start()
        dataStore = PreferenceDataStoreFactory.create(scope = testScope) {
            File.createTempFile("test_prefs", ".preferences_pb")
        }
        tokenManager = TokenManager(dataStore)
        client = OkHttpClient.Builder()
            .addInterceptor(AuthInterceptor(tokenManager))
            .build()
    }

    @After
    fun teardown() {
        server.shutdown()
    }

    @Test
    fun addsAuthHeaderForApiPaths() = runTest {
        tokenManager.saveTokens("my-jwt-token", "my-refresh-token")
        server.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(server.url("/api/sync"))
            .build()
        client.newCall(request).execute()

        val recorded = server.takeRequest()
        assertEquals("Bearer my-jwt-token", recorded.getHeader("Authorization"))
    }

    @Test
    fun skipsAuthHeaderForNonApiPaths() = runTest {
        tokenManager.saveTokens("my-jwt-token", "my-refresh-token")
        server.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(server.url("/auth/login"))
            .build()
        client.newCall(request).execute()

        val recorded = server.takeRequest()
        assertNull(recorded.getHeader("Authorization"))
    }

    @Test
    fun skipsAuthHeaderWhenNoToken() = runTest {
        server.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(server.url("/api/sync"))
            .build()
        client.newCall(request).execute()

        val recorded = server.takeRequest()
        assertNull(recorded.getHeader("Authorization"))
    }
}
