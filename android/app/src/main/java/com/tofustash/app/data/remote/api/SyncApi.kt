package com.tofustash.app.data.remote.api

import com.tofustash.app.data.remote.dto.SyncRequest
import com.tofustash.app.data.remote.dto.SyncResponse
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

interface SyncApi {

    @GET("api/sync")
    suspend fun pull(@Query("since") since: String? = null): Response<SyncResponse>

    @POST("api/sync")
    suspend fun push(@Body request: SyncRequest): Response<SyncResponse>
}
