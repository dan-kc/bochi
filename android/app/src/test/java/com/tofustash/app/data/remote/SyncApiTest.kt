package com.tofustash.app.data.remote

import com.tofustash.app.data.remote.api.SyncApi
import com.tofustash.app.data.remote.dto.HabitDto
import com.tofustash.app.data.remote.dto.SyncRequest
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory

class SyncApiTest {

    private lateinit var server: MockWebServer
    private lateinit var api: SyncApi

    @Before
    fun setup() {
        server = MockWebServer()
        server.start()
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
        api = Retrofit.Builder()
            .baseUrl(server.url("/"))
            .client(OkHttpClient())
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(SyncApi::class.java)
    }

    @After
    fun teardown() {
        server.shutdown()
    }

    @Test
    fun pullSyncWithoutSince() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"habits":[],"rewards":[],"trades":[],"tags":[],"habitTags":[],"rewardTags":[],"balance":{"tofuBalance":0.0},"serverTime":"2024-01-01T00:00:00"}"""),
        )

        val response = api.pull()
        assertTrue(response.isSuccessful)
        assertEquals(0.0, response.body()!!.balance.tofuBalance, 0.001)

        val recorded = server.takeRequest()
        assertEquals("GET", recorded.method)
        assertEquals("/api/sync", recorded.path)
    }

    @Test
    fun pullSyncWithSince() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"habits":[{"id":"h1","name":"New Habit","description":"","createdAt":"2024-06-01T00:00:00","updatedAt":"2024-06-01T00:00:00"}],"rewards":[],"trades":[],"tags":[],"habitTags":[],"rewardTags":[],"balance":{"tofuBalance":100.0},"serverTime":"2024-06-01T00:05:00"}"""),
        )

        val response = api.pull(since = "2024-03-01T00:00:00")
        assertTrue(response.isSuccessful)
        assertEquals(1, response.body()!!.habits.size)

        val recorded = server.takeRequest()
        assertEquals("/api/sync?since=2024-03-01T00%3A00%3A00", recorded.path)
    }

    @Test
    fun pushSyncSendsBody() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"habits":[{"id":"h1","name":"Exercise","description":"","createdAt":"2024-01-01T00:00:00","updatedAt":"2024-01-01T00:00:00"}],"rewards":[],"trades":[],"tags":[],"habitTags":[],"rewardTags":[],"balance":{"tofuBalance":50.0},"serverTime":"2024-01-01T00:05:00"}"""),
        )

        val request = SyncRequest(
            habits = listOf(
                HabitDto(
                    id = "h1",
                    name = "Exercise",
                    description = "",
                    createdAt = "2024-01-01T00:00:00",
                    updatedAt = "2024-01-01T00:00:00",
                ),
            ),
        )
        val response = api.push(request)
        assertTrue(response.isSuccessful)
        assertEquals(50.0, response.body()!!.balance.tofuBalance, 0.001)

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertTrue(recorded.body.readUtf8().contains("Exercise"))
    }

    @Test
    fun syncReturns401() = runTest {
        server.enqueue(MockResponse().setResponseCode(401))

        val response = api.pull()
        assertEquals(401, response.code())
    }
}
