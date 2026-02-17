package com.tofustash.app.data.repository

import com.tofustash.app.data.local.dao.TagDao
import com.tofustash.app.data.local.entity.TagEntity
import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TagRepository @Inject constructor(
    private val tagDao: TagDao,
) {
    suspend fun create(userId: String, name: String, colorHex: String): TagEntity {
        val now = Instant.now().toString()
        val tag = TagEntity(
            id = UUID.randomUUID().toString(),
            userId = userId,
            name = name,
            colorHex = colorHex,
            createdAt = now,
            updatedAt = now,
            isDirty = true,
        )
        tagDao.upsert(tag)
        return tag
    }

    suspend fun update(tag: TagEntity): TagEntity {
        val updated = tag.copy(
            updatedAt = Instant.now().toString(),
            isDirty = true,
        )
        tagDao.upsert(updated)
        return updated
    }

    suspend fun getById(id: String): TagEntity? = tagDao.getById(id)

    fun getAllActive(userId: String): Flow<List<TagEntity>> = tagDao.getAllActive(userId)

    suspend fun getDirty(userId: String): List<TagEntity> = tagDao.getDirty(userId)

    suspend fun clearDirtyFlags(ids: List<String>) = tagDao.clearDirtyFlags(ids)

    suspend fun upsertFromSync(tags: List<TagEntity>) = tagDao.upsertAll(tags)
}
