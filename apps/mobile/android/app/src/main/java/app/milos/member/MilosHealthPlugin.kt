package app.milos.member

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.result.ActivityResult
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.ActivityCallback
import com.getcapacitor.annotation.CapacitorPlugin
import java.time.Instant
import java.time.LocalDateTime
import java.time.Period
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.reflect.KClass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * ADR-172: Health Connect for the web app (`MilosHealth`, the same interface
 * as the iOS HealthKit plugin). Read-only: it asks for read access to the
 * kinds the person chose and reads a time window; the web layer shapes the
 * records and sends them to the API. Nothing is written to Health Connect,
 * nothing is read in the background.
 */
@CapacitorPlugin(name = "MilosHealth")
class MilosHealthPlugin : Plugin() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val contract = PermissionController.createRequestPermissionResultContract()

    override fun handleOnDestroy() {
        scope.cancel()
        super.handleOnDestroy()
    }

    @PluginMethod
    fun availability(call: PluginCall) {
        val result = JSObject()
        when (HealthConnectClient.getSdkStatus(context, PROVIDER)) {
            HealthConnectClient.SDK_AVAILABLE -> result.put("available", true)
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                result.put("available", false).put("reason", "update_required")
            else ->
                result.put("available", false)
                    .put("reason", if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) "not_installed" else "unsupported")
        }
        call.resolve(result)
    }

    /** Opens Play Store on Health Connect when it is missing or outdated (Android 9–13). */
    @PluginMethod
    fun openInstaller(call: PluginCall) {
        val uri = Uri.parse("market://details?id=$PROVIDER&url=healthconnect%3A%2F%2Fonboarding")
        val intent = Intent(Intent.ACTION_VIEW, uri).setPackage("com.android.vending").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
            call.resolve()
        } catch (error: Exception) {
            call.reject("store_unavailable", error)
        }
    }

    @PluginMethod
    fun requestAuthorization(call: PluginCall) {
        val kinds = kinds(call)
        val permissions = kinds.flatMap { permissionsFor(it) }.toSet()
        if (permissions.isEmpty()) {
            call.resolve(authorization(kinds, emptySet()))
            return
        }
        scope.launch {
            val client = client()
            if (client == null) {
                call.reject("unavailable")
                return@launch
            }
            val granted = client.permissionController.getGrantedPermissions()
            if (granted.containsAll(permissions)) {
                call.resolve(authorization(kinds, granted))
                return@launch
            }
            withContext(Dispatchers.Main) {
                startActivityForResult(call, contract.createIntent(context, permissions), "permissionsResult")
            }
        }
    }

    @ActivityCallback
    private fun permissionsResult(call: PluginCall?, result: ActivityResult) {
        if (call == null) return
        val granted = contract.parseResult(result.resultCode, result.data)
        call.resolve(authorization(kinds(call), granted))
    }

    @PluginMethod
    fun read(call: PluginCall) {
        val kinds = kinds(call)
        val from = call.getString("from")?.let { runCatching { Instant.parse(it) }.getOrNull() }
        val to = call.getString("to")?.let { runCatching { Instant.parse(it) }.getOrNull() }
        if (from == null || to == null || !from.isBefore(to)) {
            call.reject("invalid_window")
            return
        }
        scope.launch {
            val client = client()
            if (client == null) {
                call.reject("unavailable")
                return@launch
            }
            try {
                val granted = client.permissionController.getGrantedPermissions()
                val out = JSObject()
                if ("activities" in kinds && READ_EXERCISE in granted) out.put("workouts", workouts(client, from, to, granted))
                if ("sleep" in kinds && READ_SLEEP in granted) out.put("sleep", sleep(client, from, to))
                if ("weight" in kinds && READ_WEIGHT in granted) out.put("weights", weights(client, from, to))
                if ("resting_hr" in kinds && READ_RESTING in granted) out.put("resting_hr", restingHeartRate(client, from, to))
                if ("steps" in kinds && READ_STEPS in granted) out.put("steps", steps(client, from, to))
                call.resolve(out)
            } catch (error: Exception) {
                call.reject("read_failed", error)
            }
        }
    }

    private fun client(): HealthConnectClient? =
        if (HealthConnectClient.getSdkStatus(context, PROVIDER) == HealthConnectClient.SDK_AVAILABLE) {
            HealthConnectClient.getOrCreate(context, PROVIDER)
        } else {
            null
        }

    private fun kinds(call: PluginCall): List<String> =
        call.getArray("kinds")?.toList<String>()?.filter { it in KINDS } ?: emptyList()

    // Heart rate and distance only add numbers to a workout; the workout
    // itself needs exercise sessions.
    private fun permissionsFor(kind: String): Set<String> = when (kind) {
        "activities" -> setOf(READ_EXERCISE, READ_HEART_RATE, READ_DISTANCE)
        "sleep" -> setOf(READ_SLEEP)
        "weight" -> setOf(READ_WEIGHT)
        "resting_hr" -> setOf(READ_RESTING)
        "steps" -> setOf(READ_STEPS)
        else -> emptySet()
    }

    private fun authorization(kinds: List<String>, granted: Set<String>): JSObject {
        val required = mapOf(
            "activities" to READ_EXERCISE,
            "sleep" to READ_SLEEP,
            "weight" to READ_WEIGHT,
            "resting_hr" to READ_RESTING,
            "steps" to READ_STEPS,
        )
        return JSObject()
            .put("asked", JSArray(kinds))
            .put("granted", JSArray(kinds.filter { required[it] in granted }))
    }

    private suspend fun <T : Record> readAll(client: HealthConnectClient, type: KClass<T>, from: Instant, to: Instant): List<T> {
        val records = mutableListOf<T>()
        var token: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(recordType = type, timeRangeFilter = TimeRangeFilter.between(from, to), pageToken = token),
            )
            records += response.records
            token = response.pageToken
        } while (token != null && records.size < MAX_RECORDS)
        return records
    }

    private suspend fun workouts(client: HealthConnectClient, from: Instant, to: Instant, granted: Set<String>): JSArray {
        val rows = JSArray()
        for (session in readAll(client, ExerciseSessionRecord::class, from, to)) {
            val row = JSObject()
                .put("id", session.metadata.id)
                .put("type", exerciseType(session.exerciseType))
                .put("start", session.startTime.toString())
                .put("end", session.endTime.toString())
                .put("offset_minutes", offsetMinutes(session.startZoneOffset, session.startTime))
                .put("source_app", session.metadata.dataOrigin.packageName)
            session.title?.let { row.put("title", it) }
            val window = TimeRangeFilter.between(session.startTime, session.endTime)
            if (READ_HEART_RATE in granted) {
                val heart = client.aggregate(AggregateRequest(setOf(HeartRateRecord.BPM_AVG, HeartRateRecord.BPM_MAX), window))
                heart[HeartRateRecord.BPM_AVG]?.let { row.put("avg_hr", it) }
                heart[HeartRateRecord.BPM_MAX]?.let { row.put("max_hr", it) }
            }
            if (READ_DISTANCE in granted) {
                client.aggregate(AggregateRequest(setOf(DistanceRecord.DISTANCE_TOTAL), window))[DistanceRecord.DISTANCE_TOTAL]
                    ?.let { row.put("distance_m", it.inMeters) }
            }
            rows.put(row)
        }
        return rows
    }

    private suspend fun sleep(client: HealthConnectClient, from: Instant, to: Instant): JSArray {
        val rows = JSArray()
        for (session in readAll(client, SleepSessionRecord::class, from, to)) {
            rows.put(
                JSObject()
                    .put("id", session.metadata.id)
                    .put("start", session.startTime.toString())
                    .put("end", session.endTime.toString())
                    .put("offset_minutes", offsetMinutes(session.endZoneOffset, session.endTime))
                    .put("stage", "session"),
            )
        }
        return rows
    }

    private suspend fun weights(client: HealthConnectClient, from: Instant, to: Instant): JSArray {
        val rows = JSArray()
        for (weight in readAll(client, WeightRecord::class, from, to)) {
            rows.put(
                JSObject()
                    .put("id", weight.metadata.id)
                    .put("at", weight.time.toString())
                    .put("offset_minutes", offsetMinutes(weight.zoneOffset, weight.time))
                    .put("kg", weight.weight.inKilograms),
            )
        }
        return rows
    }

    // One average per local day.
    private suspend fun restingHeartRate(client: HealthConnectClient, from: Instant, to: Instant): JSArray {
        val rows = JSArray()
        readAll(client, RestingHeartRateRecord::class, from, to)
            .groupBy { record ->
                val offset = record.zoneOffset ?: ZoneId.systemDefault().rules.getOffset(record.time)
                record.time.atOffset(offset).toLocalDate().toString()
            }
            .toSortedMap()
            .forEach { (day, records) ->
                rows.put(JSObject().put("date", day).put("bpm", records.map { it.beatsPerMinute }.average()))
            }
        return rows
    }

    // Health Connect merges phone and watch counts in its aggregate.
    private suspend fun steps(client: HealthConnectClient, from: Instant, to: Instant): JSArray {
        val zone = ZoneId.systemDefault()
        val start = LocalDateTime.ofInstant(from, zone).toLocalDate().atStartOfDay()
        val end = LocalDateTime.ofInstant(to, zone)
        val rows = JSArray()
        client.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(start, end),
                timeRangeSlicer = Period.ofDays(1),
            ),
        ).forEach { bucket ->
            bucket.result[StepsRecord.COUNT_TOTAL]?.let { count ->
                rows.put(JSObject().put("date", bucket.startTime.toLocalDate().toString()).put("count", count))
            }
        }
        return rows
    }

    private fun offsetMinutes(offset: ZoneOffset?, at: Instant): Int =
        (offset ?: ZoneId.systemDefault().rules.getOffset(at)).totalSeconds / 60

    // Named like Garmin's activity types, so the server folds every provider
    // into the same sports.
    private fun exerciseType(type: Int): String = when (type) {
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING -> "RUNNING"
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL -> "TREADMILL_RUNNING"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING -> "CYCLING"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY -> "INDOOR_CYCLING"
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL -> "LAP_SWIMMING"
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER -> "OPEN_WATER_SWIMMING"
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> "WALKING"
        ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> "HIKING"
        ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING,
        ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING,
        ExerciseSessionRecord.EXERCISE_TYPE_CALISTHENICS -> "STRENGTH_TRAINING"
        ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING -> "HIIT"
        ExerciseSessionRecord.EXERCISE_TYPE_BOOT_CAMP -> "BOOTCAMP"
        ExerciseSessionRecord.EXERCISE_TYPE_YOGA -> "YOGA"
        ExerciseSessionRecord.EXERCISE_TYPE_PILATES -> "PILATES"
        ExerciseSessionRecord.EXERCISE_TYPE_ROWING_MACHINE -> "INDOOR_ROWING"
        ExerciseSessionRecord.EXERCISE_TYPE_ROWING -> "ROWING"
        ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL -> "ELLIPTICAL"
        ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING -> "STAIR_CLIMBING"
        ExerciseSessionRecord.EXERCISE_TYPE_SKIING -> "SKIING"
        else -> "OTHER"
    }

    companion object {
        private const val PROVIDER = "com.google.android.apps.healthdata"
        private const val MAX_RECORDS = 1000
        private val KINDS = setOf("activities", "sleep", "weight", "resting_hr", "steps")
        private val READ_EXERCISE = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
        private val READ_HEART_RATE = HealthPermission.getReadPermission(HeartRateRecord::class)
        private val READ_DISTANCE = HealthPermission.getReadPermission(DistanceRecord::class)
        private val READ_SLEEP = HealthPermission.getReadPermission(SleepSessionRecord::class)
        private val READ_WEIGHT = HealthPermission.getReadPermission(WeightRecord::class)
        private val READ_RESTING = HealthPermission.getReadPermission(RestingHeartRateRecord::class)
        private val READ_STEPS = HealthPermission.getReadPermission(StepsRecord::class)
    }
}
