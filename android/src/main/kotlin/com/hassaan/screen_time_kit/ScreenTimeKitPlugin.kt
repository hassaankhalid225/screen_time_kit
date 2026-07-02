package com.hassaan.screen_time_kit

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.Calendar

/**
 * Android implementation of `screen_time_kit`.
 *
 * Backed by [UsageStatsManager] for usage stats and [AppOpsManager] for the
 * usage-access permission check. App limits are implemented as *soft* limits —
 * see [startLimitMonitor] — because Android exposes no OS-level API to block a
 * third-party app. The plugin can only detect a crossing and notify Dart; it
 * cannot force-close another app. This is intentional and documented.
 */
class ScreenTimeKitPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    EventChannel.StreamHandler {

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null

    // Lazy so the plugin can be instantiated in plain JUnit tests (no Looper).
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var monitorRunnable: Runnable? = null
    /** Package -> epoch-day on which we last emitted a limit event, to fire once per day. */
    private val notifiedOn = HashMap<String, Long>()

    private companion object {
        const val PREFS = "screen_time_kit.limits"
        const val METHOD_CHANNEL = "screen_time_kit"
        const val EVENT_CHANNEL = "screen_time_kit/limit_events"
        const val MONITOR_INTERVAL_MS = 60_000L
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        stopLimitMonitor()
    }

    // region ActivityAware — needed to launch the Usage-access settings screen.
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }
    // endregion

    // region EventChannel
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        startLimitMonitor()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
    // endregion

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "checkPermissionStatus" -> result.success(permissionStatus())
            "requestPermission" -> requestPermission(result)
            "openSettings" -> openUsageAccessSettings(result)
            "getAppUsage" -> getAppUsage(call, result)
            "setAppLimit" -> setAppLimit(call, result)
            "removeAppLimit" -> removeAppLimit(call, result)
            "getActiveLimits" -> result.success(activeLimits())
            "clearAllLimits" -> {
                limitsPrefs().edit().clear().apply()
                notifiedOn.clear()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // region Permissions (5.2)

    private fun hasUsageAccessPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun permissionStatus(): String =
        if (hasUsageAccessPermission()) "granted" else "denied"

    /**
     * There is no runtime dialog for [android.Manifest.permission.PACKAGE_USAGE_STATS].
     * The best we can do is open the settings screen; the caller re-checks status
     * afterwards (Dart returns whatever the current state is at return time).
     */
    private fun requestPermission(result: Result) {
        if (hasUsageAccessPermission()) {
            result.success("granted")
            return
        }
        openUsageAccessSettings(null)
        result.success(permissionStatus())
    }

    private fun openUsageAccessSettings(result: Result?) {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        val activity = activityBinding?.activity
        if (activity != null) {
            activity.startActivity(intent)
        } else {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
        result?.success(null)
    }

    // endregion

    // region Usage stats (5.3)

    private fun getAppUsage(call: MethodCall, result: Result) {
        if (!hasUsageAccessPermission()) {
            result.error(
                "PERMISSION_DENIED",
                "Usage-access permission has not been granted.",
                null,
            )
            return
        }
        val start = (call.argument<Number>("startMillis"))?.toLong() ?: 0L
        val end = (call.argument<Number>("endMillis"))?.toLong() ?: System.currentTimeMillis()

        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        // queryAndAggregateUsageStats collapses the daily buckets into one entry
        // per package for the whole [start, end] window, avoiding double-counting.
        val aggregated = usm.queryAndAggregateUsageStats(start, end)
        val pm = context.packageManager

        val payload = aggregated.values
            .filter { it.totalTimeInForeground > 0 }
            .map { stats ->
                val pkg = stats.packageName
                val label = try {
                    val info = pm.getApplicationInfo(pkg, 0)
                    pm.getApplicationLabel(info).toString()
                } catch (_: Exception) {
                    // Package not visible (Android 11+ visibility) or uninstalled.
                    pkg
                }
                mapOf(
                    "packageName" to pkg,
                    "appName" to label,
                    "usageMillis" to stats.totalTimeInForeground,
                    "dateMillis" to start,
                )
            }
        result.success(payload)
    }

    // endregion

    // region App limits (5.4) — soft limits

    private fun limitsPrefs() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun setAppLimit(call: MethodCall, result: Result) {
        val pkg = call.argument<String>("packageName")
        val limitMillis = call.argument<Number>("limitMillis")?.toLong()
        if (pkg == null || limitMillis == null) {
            result.error("INVALID_ARGS", "packageName and limitMillis are required.", null)
            return
        }
        limitsPrefs().edit().putLong(pkg, limitMillis).apply()
        notifiedOn.remove(pkg)
        result.success(null)
    }

    private fun removeAppLimit(call: MethodCall, result: Result) {
        val pkg = call.argument<String>("packageName")
        if (pkg == null) {
            result.error("INVALID_ARGS", "packageName is required.", null)
            return
        }
        limitsPrefs().edit().remove(pkg).apply()
        notifiedOn.remove(pkg)
        result.success(null)
    }

    private fun activeLimits(): List<Map<String, Any?>> =
        limitsPrefs().all.entries
            .mapNotNull { (pkg, value) ->
                (value as? Long)?.let {
                    mapOf("packageName" to pkg, "limitMillis" to it)
                }
            }

    /**
     * Polls today's usage on a fixed interval while a Dart listener is attached.
     *
     * When a limited app's usage crosses its threshold we emit one event per day.
     * NOTE: this only runs while the Flutter engine is alive. Enforcing limits
     * after the host app is killed requires the *host* app to run its own
     * foreground service / WorkManager job — this plugin deliberately does not
     * spawn one for you. Documented in the README.
     */
    private fun startLimitMonitor() {
        if (monitorRunnable != null) return
        val runnable = object : Runnable {
            override fun run() {
                checkLimits()
                mainHandler.postDelayed(this, MONITOR_INTERVAL_MS)
            }
        }
        monitorRunnable = runnable
        mainHandler.post(runnable)
    }

    private fun stopLimitMonitor() {
        monitorRunnable?.let { mainHandler.removeCallbacks(it) }
        monitorRunnable = null
    }

    private fun checkLimits() {
        val sink = eventSink ?: return
        val limits = limitsPrefs().all
        if (limits.isEmpty() || !hasUsageAccessPermission()) return

        val startOfDay = startOfToday()
        val now = System.currentTimeMillis()
        val today = now / 86_400_000L

        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val usageByPkg = usm.queryAndAggregateUsageStats(startOfDay, now)

        for ((pkg, value) in limits) {
            val limitMillis = (value as? Long) ?: continue
            if (notifiedOn[pkg] == today) continue
            val used = usageByPkg[pkg]?.totalTimeInForeground ?: 0L
            if (used >= limitMillis) {
                notifiedOn[pkg] = today
                sink.success(
                    mapOf(
                        "packageName" to pkg,
                        "limitMillis" to limitMillis,
                        "reachedAtMillis" to now,
                    ),
                )
            }
        }
    }

    private fun startOfToday(): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    // endregion
}
