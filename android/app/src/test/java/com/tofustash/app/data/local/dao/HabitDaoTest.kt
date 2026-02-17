package com.tofustash.app.data.local.dao

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.tofustash.app.data.local.db.TofustashDatabase
import com.tofustash.app.data.local.entity.HabitEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class HabitDaoTest {

    private lateinit var db: TofustashDatabase
    private lateinit var dao: HabitDao

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TofustashDatabase::class.java,
        ).allowMainThreadQueries().build()
        dao = db.habitDao()
    }

    @After
    fun teardown() {
        db.close()
    }

    private fun makeHabit(
        id: String = UUID.randomUUID().toString(),
        name: String = "Test Habit",
        description: String = "",
        deletedAt: String? = null,
        isDirty: Boolean = false,
        difficultyRank: String? = null,
        minDailyFrequency: Double? = null,
        hiddenUntil: String? = null,
    ) = HabitEntity(
        id = id,
        userId = "user-1",
        name = name,
        description = description,
        createdAt = "2024-01-01T00:00:00",
        updatedAt = "2024-01-01T00:00:00",
        deletedAt = deletedAt,
        hiddenUntil = hiddenUntil,
        minDailyFrequency = minDailyFrequency,
        difficultyRank = difficultyRank,
        isDirty = isDirty,
    )

    @Test
    fun insertAndGetById() = runTest {
        val habit = makeHabit(name = "Exercise")
        dao.upsert(habit)

        val result = dao.getById(habit.id)
        assertNotNull(result)
        assertEquals("Exercise", result!!.name)
    }

    @Test
    fun upsertOverwritesExisting() = runTest {
        val id = UUID.randomUUID().toString()
        dao.upsert(makeHabit(id = id, name = "Old Name"))
        dao.upsert(makeHabit(id = id, name = "New Name"))

        val result = dao.getById(id)
        assertEquals("New Name", result!!.name)
    }

    @Test
    fun getAllActiveExcludesSoftDeleted() = runTest {
        dao.upsert(makeHabit(name = "Active"))
        dao.upsert(makeHabit(name = "Deleted", deletedAt = "2024-01-02T00:00:00"))

        val results = dao.getAllActive("user-1").first()
        assertEquals(1, results.size)
        assertEquals("Active", results[0].name)
    }

    @Test
    fun getAllActiveFiltersByUserId() = runTest {
        dao.upsert(makeHabit(name = "Mine"))
        dao.upsert(
            HabitEntity(
                id = UUID.randomUUID().toString(),
                userId = "other-user",
                name = "Theirs",
                description = "",
                createdAt = "2024-01-01T00:00:00",
                updatedAt = "2024-01-01T00:00:00",
                deletedAt = null,
                hiddenUntil = null,
                minDailyFrequency = null,
                difficultyRank = null,
                isDirty = false,
            ),
        )

        val results = dao.getAllActive("user-1").first()
        assertEquals(1, results.size)
        assertEquals("Mine", results[0].name)
    }

    @Test
    fun getDirtyReturnsOnlyDirtyEntities() = runTest {
        dao.upsert(makeHabit(name = "Clean", isDirty = false))
        dao.upsert(makeHabit(name = "Dirty", isDirty = true))

        val dirty = dao.getDirty("user-1")
        assertEquals(1, dirty.size)
        assertEquals("Dirty", dirty[0].name)
    }

    @Test
    fun clearDirtyFlagsByIds() = runTest {
        val id1 = UUID.randomUUID().toString()
        val id2 = UUID.randomUUID().toString()
        dao.upsert(makeHabit(id = id1, name = "Dirty 1", isDirty = true))
        dao.upsert(makeHabit(id = id2, name = "Dirty 2", isDirty = true))

        dao.clearDirtyFlags(listOf(id1, id2))

        val dirty = dao.getDirty("user-1")
        assertTrue(dirty.isEmpty())
    }

    @Test
    fun getByIdReturnsNullForMissing() = runTest {
        val result = dao.getById("nonexistent")
        assertNull(result)
    }

    @Test
    fun upsertAllInsertsMultiple() = runTest {
        val habits = listOf(
            makeHabit(name = "Habit 1"),
            makeHabit(name = "Habit 2"),
            makeHabit(name = "Habit 3"),
        )
        dao.upsertAll(habits)

        val results = dao.getAllActive("user-1").first()
        assertEquals(3, results.size)
    }

    @Test
    fun softDeleteSetsDirtyFlag() = runTest {
        val id = UUID.randomUUID().toString()
        dao.upsert(makeHabit(id = id, isDirty = false))

        dao.softDelete(id, "2024-06-01T00:00:00", "2024-06-01T00:00:00")

        val result = dao.getById(id)
        assertNotNull(result!!.deletedAt)
        assertTrue(result.isDirty)
    }

    @Test
    fun getUpdatedSinceReturnsRecentlyUpdated() = runTest {
        dao.upsert(makeHabit(name = "Old").copy(updatedAt = "2024-01-01T00:00:00"))
        dao.upsert(makeHabit(name = "New").copy(updatedAt = "2024-06-01T00:00:00"))

        val results = dao.getUpdatedSince("user-1", "2024-03-01T00:00:00")
        assertEquals(1, results.size)
        assertEquals("New", results[0].name)
    }
}
