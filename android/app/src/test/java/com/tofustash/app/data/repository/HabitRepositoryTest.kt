package com.tofustash.app.data.repository

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.tofustash.app.data.local.db.TofustashDatabase
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

@RunWith(RobolectricTestRunner::class)
class HabitRepositoryTest {

    private lateinit var db: TofustashDatabase
    private lateinit var repo: HabitRepository
    private val userId = "user-1"

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TofustashDatabase::class.java,
        ).allowMainThreadQueries().build()
        repo = HabitRepository(db.habitDao())
    }

    @After
    fun teardown() {
        db.close()
    }

    @Test
    fun createHabitSetsIdAndTimestampsAndDirtyFlag() = runTest {
        val habit = repo.create(userId, "Exercise", "30 min cardio")

        assertNotNull(habit.id)
        assertNotNull(habit.createdAt)
        assertNotNull(habit.updatedAt)
        assertTrue(habit.isDirty)
        assertEquals("Exercise", habit.name)
        assertEquals("30 min cardio", habit.description)
        assertEquals(userId, habit.userId)
    }

    @Test
    fun createHabitPersistsToDb() = runTest {
        val habit = repo.create(userId, "Exercise", "")
        val retrieved = repo.getById(habit.id)
        assertNotNull(retrieved)
        assertEquals("Exercise", retrieved!!.name)
    }

    @Test
    fun getAllActiveReturnsOnlyNonDeleted() = runTest {
        repo.create(userId, "Active Habit", "")
        val habit2 = repo.create(userId, "To Delete", "")
        repo.softDelete(habit2.id)

        val active = repo.getAllActive(userId).first()
        assertEquals(1, active.size)
        assertEquals("Active Habit", active[0].name)
    }

    @Test
    fun updateHabitSetsUpdatedAtAndDirtyFlag() = runTest {
        val habit = repo.create(userId, "Original", "")
        val updated = repo.update(habit.copy(name = "Updated", isDirty = false))

        assertEquals("Updated", updated.name)
        assertTrue(updated.isDirty)
        assertTrue(updated.updatedAt >= habit.updatedAt)
    }

    @Test
    fun softDeleteSetsDeletedAtAndDirtyFlag() = runTest {
        val habit = repo.create(userId, "To Delete", "")
        repo.softDelete(habit.id)

        val deleted = repo.getById(habit.id)
        assertNotNull(deleted!!.deletedAt)
        assertTrue(deleted.isDirty)
    }

    @Test
    fun getDirtyReturnsOnlyDirtyEntities() = runTest {
        val habit = repo.create(userId, "Dirty", "")
        // Clear dirty flag to simulate synced state
        db.habitDao().clearDirtyFlags(listOf(habit.id))

        repo.create(userId, "Still Dirty", "")

        val dirty = repo.getDirty(userId)
        assertEquals(1, dirty.size)
        assertEquals("Still Dirty", dirty[0].name)
    }
}
