package com.tofustash.app.data.remote

import com.tofustash.app.data.remote.dto.AuthResponse
import com.tofustash.app.data.remote.dto.BalanceDto
import com.tofustash.app.data.remote.dto.ErrorResponse
import com.tofustash.app.data.remote.dto.HabitDto
import com.tofustash.app.data.remote.dto.HabitTagDto
import com.tofustash.app.data.remote.dto.LoginRequest
import com.tofustash.app.data.remote.dto.RewardDto
import com.tofustash.app.data.remote.dto.SyncResponse
import com.tofustash.app.data.remote.dto.TagDto
import com.tofustash.app.data.remote.dto.TradeDto
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DtoSerializationTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun loginRequestSerializes() {
        val request = LoginRequest("test@example.com", "password123")
        val serialized = json.encodeToString(LoginRequest.serializer(), request)
        assertEquals("""{"email":"test@example.com","password":"password123"}""", serialized)
    }

    @Test
    fun authResponseDeserializes() {
        val body = """{"accessToken":"jwt-token","refreshToken":"refresh-token"}"""
        val response = json.decodeFromString(AuthResponse.serializer(), body)
        assertEquals("jwt-token", response.accessToken)
        assertEquals("refresh-token", response.refreshToken)
    }

    @Test
    fun syncResponseDeserializes() {
        val body = """
        {
            "habits": [{"id":"h1","name":"Exercise","description":"","createdAt":"2024-01-01T00:00:00","updatedAt":"2024-01-01T00:00:00"}],
            "rewards": [],
            "trades": [{"id":"t1","habitId":"h1","amount":100,"createdAt":"2024-01-01T00:00:00","updatedAt":"2024-01-01T00:00:00"}],
            "tags": [{"id":"tag1","name":"Health","colorHex":"#FF0000","createdAt":"2024-01-01T00:00:00","updatedAt":"2024-01-01T00:00:00"}],
            "habitTags": [{"habitId":"h1","tagId":"tag1","createdAt":"2024-01-01T00:00:00","updatedAt":"2024-01-01T00:00:00"}],
            "rewardTags": [],
            "balance": {"tofuBalance": 42.5},
            "serverTime": "2024-01-01T00:05:00",
            "email": "user@example.com",
            "isPremium": false
        }
        """.trimIndent()

        val response = json.decodeFromString(SyncResponse.serializer(), body)
        assertEquals(1, response.habits.size)
        assertEquals("Exercise", response.habits[0].name)
        assertEquals(1, response.trades.size)
        assertEquals(100, response.trades[0].amount)
        assertEquals(42.5, response.balance.tofuBalance, 0.001)
        assertEquals("2024-01-01T00:05:00", response.serverTime)
        assertEquals("user@example.com", response.email)
    }

    @Test
    fun habitDtoHandlesNullableFields() {
        val body = """{"id":"h1","name":"Test","description":"","createdAt":"2024-01-01T00:00:00","updatedAt":"2024-01-01T00:00:00"}"""
        val habit = json.decodeFromString(HabitDto.serializer(), body)
        assertNull(habit.deletedAt)
        assertNull(habit.hiddenUntil)
        assertNull(habit.minDailyFrequency)
        assertNull(habit.difficultyRank)
    }

    @Test
    fun rewardDtoHandlesAllFields() {
        val body = """{"id":"r1","name":"Chocolate","description":"Yummy","createdAt":"2024-01-01T00:00:00","updatedAt":"2024-01-01T00:00:00","deletedAt":null,"hiddenUntil":"2024-06-01T00:00:00","maxDailyFrequency":2.0,"damageRank":"MILD"}"""
        val reward = json.decodeFromString(RewardDto.serializer(), body)
        assertEquals("Chocolate", reward.name)
        assertEquals(2.0, reward.maxDailyFrequency!!, 0.001)
        assertEquals("MILD", reward.damageRank)
    }

    @Test
    fun errorResponseDeserializes() {
        val body = """{"errors":[{"code":"INVALID_LOGIN_CREDENTIALS","message":"Wrong email or password"}]}"""
        val error = json.decodeFromString(ErrorResponse.serializer(), body)
        assertEquals(1, error.errors.size)
        assertEquals("INVALID_LOGIN_CREDENTIALS", error.errors[0].code)
    }

    @Test
    fun syncResponseIgnoresUnknownKeys() {
        val body = """
        {
            "habits": [],
            "rewards": [],
            "trades": [],
            "tags": [],
            "habitTags": [],
            "rewardTags": [],
            "balance": {"tofuBalance": 0.0},
            "serverTime": "2024-01-01T00:00:00",
            "unknownField": "should be ignored"
        }
        """.trimIndent()

        val response = json.decodeFromString(SyncResponse.serializer(), body)
        assertEquals(0.0, response.balance.tofuBalance, 0.001)
    }
}
