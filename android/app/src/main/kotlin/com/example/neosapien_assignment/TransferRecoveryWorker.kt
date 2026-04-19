package com.example.neosapien_assignment

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class TransferRecoveryWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        // Scaffold only: a real implementation would resume chunked transfer state.
        val transferId = inputData.getString(KEY_TRANSFER_ID) ?: return Result.failure()
        val direction = inputData.getString(KEY_DIRECTION) ?: "unknown"
        android.util.Log.i(
            "NeoSapienRecovery",
            "Scheduled recovery worker running for transfer=$transferId direction=$direction"
        )
        return Result.success()
    }

    companion object {
        const val KEY_TRANSFER_ID = "transfer_id"
        const val KEY_DIRECTION = "direction"
    }
}
