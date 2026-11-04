package com.globalspeed.globalspeed_mobile

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.ScanResult
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.PhysicalChannelConfig
import android.telephony.SubscriptionManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyDisplayInfo
import android.telephony.TelephonyManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * 通过平台通道向 Flutter 暴露「当前链路」信息：
 * 连接类型、WiFi 制式/频段/带宽/信号、蜂窝制式/频段/信号，以及定位省份。
 *
 * 所有采集都做权限与异常兜底：拿不到的字段直接不返回，由 Dart 侧隐藏。
 */
class NetLink(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "globalspeed/netlink"
        private const val REQ_CODE = 4711
        private val RUNTIME_PERMS = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.READ_PHONE_STATE,
        )
    }

    private var channel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var overrideNetworkType = 0
    private var displayNetworkType = 0
    private var telephonyCallback: Any? = null
    private var registeredSubId = Int.MIN_VALUE

    // 来自 PhysicalChannelConfig 的下行带宽（kHz）与频段，是读 4G/5G 频宽最靠谱的公开来源
    private var pcBandwidthKhz = 0
    private var pcBand = 0
    private var pcIsNr = false
    private val main = Handler(Looper.getMainLooper())

    fun attach(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
        ensureTelephony()
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        unregisterTelephony()
        registeredSubId = Int.MIN_VALUE
    }

    // ------------------------------------------------------------ 双卡：始终跟随「数据卡」

    /** 当前数据卡的 subscriptionId；取不到时退回默认值。 */
    private fun dataSubId(): Int = try {
        SubscriptionManager.getDefaultDataSubscriptionId()
    } catch (_: Throwable) {
        SubscriptionManager.DEFAULT_SUBSCRIPTION_ID
    }

    /**
     * 绑定到数据卡的 TelephonyManager。
     * 双卡机型切卡后如果不按 subId 取实例，拿到的永远是默认（第一张）卡的信息。
     */
    private fun telephony(): TelephonyManager? {
        val base = activity.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return null
        val subId = dataSubId()
        if (subId < 0) return base
        return try {
            base.createForSubscriptionId(subId)
        } catch (_: Throwable) {
            base
        }
    }

    /** 数据卡变了就重新注册回调，保证 DisplayInfo / PhysicalChannelConfig 都跟着新卡。 */
    private fun ensureTelephony() {
        val subId = dataSubId()
        if (subId == registeredSubId) return
        unregisterTelephony()
        registeredSubId = subId
        registerTelephony()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> result.success(snapshot())
            "permissions" -> result.success(permissionMap())
            "request" -> requestPermissions(result)
            "location" -> location(result)
            "version" -> result.success(versionMap())
            else -> result.notImplemented()
        }
    }

    /** 版本号直接从 APK 读，保证设置页显示的就是当前安装包。 */
    private fun versionMap(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        try {
            val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
            out["name"] = info.versionName ?: ""
            out["code"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        } catch (_: Throwable) {
        }
        return out
    }

    fun onPermissionResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != REQ_CODE) return
        val res = pendingResult
        pendingResult = null
        res?.success(permissionMap())
    }

    // ------------------------------------------------------------ 权限

    private fun granted(perm: String): Boolean =
        activity.checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED

    private fun hasLocation(): Boolean = granted(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun permissionMap(): Map<String, Any> = mapOf(
        "location" to hasLocation(),
        "phone" to granted(Manifest.permission.READ_PHONE_STATE),
    )

    private fun requestPermissions(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(permissionMap())
            return
        }
        val missing = RUNTIME_PERMS.filter { !granted(it) }
        if (missing.isEmpty()) {
            result.success(permissionMap())
            return
        }
        if (pendingResult != null) {
            result.success(permissionMap())
            return
        }
        pendingResult = result
        try {
            activity.requestPermissions(missing.toTypedArray(), REQ_CODE)
        } catch (e: Exception) {
            pendingResult = null
            result.success(permissionMap())
        }
    }

    // ------------------------------------------------------------ 链路快照

    @SuppressLint("MissingPermission")
    private fun snapshot(): Map<String, Any?> {
        ensureTelephony()
        val out = HashMap<String, Any?>()
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val active = cm?.activeNetwork
        val caps = active?.let { cm?.getNetworkCapabilities(it) }
        val vpnActive = activity.checkSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE) ==
            PackageManager.PERMISSION_GRANTED &&
            active != null && cm?.getNetworkCapabilities(active)?.let {
                it.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            } == true

        var type = "none"
        var metered = false
        if (caps != null) {
            type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                else -> "other"
            }
            metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        }
        out["type"] = type
        out["vpn"] = vpnActive && type != "vpn"
        out["metered"] = metered
        out["operatorName"] = operatorName()

        if (type == "cellular" || type == "vpn") {
            out["cell"] = cellInfo()
        }
        if (type == "wifi") {
            out["wifi"] = wifiInfo()
        }
        return out
    }

    private fun operatorName(): String {
        val tm = telephony() ?: return ""
        return try {
            // 数据卡的运营商；没有卡信息时退回网络侧名称
            tm.simOperatorName.ifEmpty { tm.networkOperatorName }.orEmpty()
        } catch (_: Throwable) {
            ""
        }
    }

    @SuppressLint("MissingPermission")
    private fun wifiInfo(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        val wm = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return out
        val info: WifiInfo = try {
            wm.connectionInfo
        } catch (_: Throwable) {
            return out
        } ?: return out

        val freq = info.frequency
        if (freq > 0) out["freqMhz"] = freq
        if (info.rssi < 0) out["rssi"] = info.rssi
        if (info.linkSpeed > 0) out["linkSpeed"] = info.linkSpeed
        val standard = wifiStandardName(info)
        if (standard.isNotEmpty()) out["standard"] = standard
        val width = channelWidthMhz(wm, info)
        if (width > 0) out["bandwidthMhz"] = width
        return out
    }

    private fun wifiStandardName(info: WifiInfo): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return ""
        return try {
            when (info.wifiStandard) {
                ScanResult.WIFI_STANDARD_11N -> "WiFi4"
                ScanResult.WIFI_STANDARD_11AC -> "WiFi5"
                ScanResult.WIFI_STANDARD_11AX -> "WiFi6"
                ScanResult.WIFI_STANDARD_11AD -> "WiFi5"
                ScanResult.WIFI_STANDARD_11BE -> "WiFi7"
                else -> ""
            }
        } catch (_: Throwable) {
            ""
        }
    }

    /**
     * 信道带宽没有公开 API：
     * 1) 先反射 `WifiInfo.getChannelWidth()`（多数 ROM 可用）；
     * 2) 不行就从扫描结果里按 BSSID 找同名 AP 的 `channelWidth`；
     * 3) 都拿不到返回 0，由上层隐藏。
     */
    private fun channelWidthMhz(wm: WifiManager, info: WifiInfo): Int {
        try {
            val m = WifiInfo::class.java.getMethod("getChannelWidth")
            val v = m.invoke(info) as? Int ?: 0
            if (v in intArrayOf(20, 40, 80, 160, 320)) return v
        } catch (_: Throwable) {
        }
        val bssid = try {
            info.bssid
        } catch (_: Throwable) {
            null
        }
        if (bssid.isNullOrEmpty()) return 0
        return try {
            val result = wm.scanResults.firstOrNull {
                it.BSSID?.equals(bssid, true) == true
            } ?: return 0
            when (result.channelWidth) {
                ScanResult.CHANNEL_WIDTH_20MHZ -> 20
                ScanResult.CHANNEL_WIDTH_40MHZ -> 40
                ScanResult.CHANNEL_WIDTH_80MHZ -> 80
                ScanResult.CHANNEL_WIDTH_160MHZ -> 160
                ScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> 160
                else -> 0
            }
        } catch (_: Throwable) {
            0
        }
    }

    @SuppressLint("MissingPermission")
    private fun cellInfo(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        // 必须用数据卡的 TelephonyManager，否则双卡机型会一直读到第一张卡
        val tm = telephony() ?: return out

        var dataType = -1
        if (granted(Manifest.permission.READ_PHONE_STATE)) {
            try {
                dataType = tm.dataNetworkType
            } catch (_: Throwable) {
            }
        }
        if (dataType <= 0 && displayNetworkType > 0) dataType = displayNetworkType
        if (dataType > 0) out["networkType"] = dataType

        // NSA 5G：数据网络仍是 LTE，但 DisplayInfo 上报了 NR 覆盖
        val nr = dataType == TelephonyManager.NETWORK_TYPE_NR || overrideNetworkType >= 3
        out["nr"] = nr

        // PhysicalChannelConfig 给的带宽最准（4G/5G 都可能有，5G 部分平台为空）
        val pcBw = pcBandwidthKhz / 1000
        if (pcBw > 0) {
            if (pcIsNr || nr) {
                out["nrBandwidthMhz"] = pcBw
            } else {
                out["lteBandwidthMhz"] = pcBw
            }
        }
        if (pcBand > 0) {
            if (pcIsNr || nr) {
                if (!out.containsKey("nrBand")) out["nrBand"] = "n$pcBand"
            } else {
                if (!out.containsKey("lteBand")) out["lteBand"] = "B$pcBand"
            }
        }

        if (!hasLocation()) return out
        val cells = try {
            tm.allCellInfo
        } catch (_: Throwable) {
            null
        } ?: return out

        // 只认数据卡所在的那张网：优先「已注册」，再按 PhysicalChannelConfig 的制式过滤
        val registered = cells.filter { it.isRegistered }
        val target = registered.firstOrNull {
            (pcIsNr && it is CellInfoNr) || (!pcIsNr && it is CellInfoLte)
        } ?: registered.firstOrNull()

        for (ci in listOfNotNull(target)) {
            when (ci) {
                is CellInfoNr -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        (ci.cellIdentity as? CellIdentityNr)?.let { id ->
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                if (!out.containsKey("nrBand")) {
                                    id.bands?.firstOrNull()?.let { out["nrBand"] = "n$it" }
                                }
                            }
                        }
                        val ss = ci.cellSignalStrength as? CellSignalStrengthNr
                        if (ss != null && ss.ssRsrp != Int.MAX_VALUE) out["rsrp"] = ss.ssRsrp
                        if (ss != null && ss.ssSinr != Int.MAX_VALUE) out["sinr"] = ss.ssSinr
                        out["nr"] = true
                    }
                }
                is CellInfoLte -> {
                    val ss = ci.cellSignalStrength as? CellSignalStrengthLte
                    if (ss != null && ss.rsrp != Int.MAX_VALUE) out["rsrp"] = ss.rsrp
                    (ci.cellIdentity as? CellIdentityLte)?.let { id ->
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            if (!out.containsKey("lteBand")) {
                                id.bands?.firstOrNull()?.let { out["lteBand"] = "B$it" }
                            }
                        }
                        if (!out.containsKey("lteBandwidthMhz")) {
                            try {
                                val bw = id.bandwidth
                                if (bw in intArrayOf(1, 3, 5, 10, 15, 20)) {
                                    out["lteBandwidthMhz"] = bw
                                }
                            } catch (_: Throwable) {
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    // ------------------------------------------------------------ 定位

    @SuppressLint("MissingPermission")
    private fun location(result: MethodChannel.Result) {
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)
        fun reply(map: Map<String, Any?>?) {
            if (!replied.compareAndSet(false, true)) return
            result.success(map)
        }

        if (!hasLocation()) {
            reply(null)
            return
        }
        val lm = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm == null) {
            reply(null)
            return
        }
        val last = bestLastKnown(lm)
        if (last != null && System.currentTimeMillis() - last.time < 10 * 60 * 1000) {
            resolvePlace(last, ::reply)
            return
        }
        // 单次定位最多等 4 秒，超时就直接用地标或返回空，避免界面一直「获取中」
        main.postDelayed({
            removeFixListeners(lm)
            val fallback = last ?: bestLastKnown(lm)
            if (fallback != null) resolvePlace(fallback, ::reply) else reply(null)
        }, 4000)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                lm.getCurrentLocation(
                    LocationManager.NETWORK_PROVIDER, null, activity.mainExecutor,
                ) { loc ->
                    val target = loc ?: last ?: bestLastKnown(lm)
                    if (target == null) requestSingleFix(lm, ::reply) else resolvePlace(target, ::reply)
                }
                return
            } catch (_: Throwable) {
            }
        }
        if (last != null) resolvePlace(last, ::reply) else requestSingleFix(lm, ::reply)
    }

    private val fixListeners = mutableListOf<Pair<LocationManager, LocationListener>>()

    private fun removeFixListeners(lm: LocationManager) {
        for ((manager, listener) in fixListeners) {
            try {
                manager.removeUpdates(listener)
            } catch (_: Throwable) {
            }
        }
        fixListeners.clear()
    }

    /// 部分机型/没有 Google 服务的设备上 lastKnown 为空，主动挂一次定位更新兜底。
    @SuppressLint("MissingPermission")
    private fun requestSingleFix(lm: LocationManager, emit: (Map<String, Any?>) -> Unit) {
        if (fixListeners.isNotEmpty()) return
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                removeFixListeners(lm)
                resolvePlace(location, emit)
            }

            override fun onProviderEnabled(provider: String) {}

            override fun onProviderDisabled(provider: String) {}

            @Deprecated("deprecated in API 29")
            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
        }
        for (provider in listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
        )) {
            try {
                if (!lm.isProviderEnabled(provider)) continue
                lm.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
                fixListeners.add(lm to listener)
            } catch (_: Throwable) {
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun bestLastKnown(lm: LocationManager): Location? {
        var best: Location? = null
        for (provider in listOf(
            LocationManager.NETWORK_PROVIDER,
            LocationManager.GPS_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        )) {
            try {
                val loc = lm.getLastKnownLocation(provider) ?: continue
                if (best == null || loc.time > best.time) best = loc
            } catch (_: Throwable) {
            }
        }
        return best
    }

    /// 反向地理编码可能没网/超时，最多等 1.5 秒，拿不到就只返回经纬度，
    /// 由 Dart 侧用离线省界兜底 —— 绝不让诊断页一直卡在「获取中」。
    private fun resolvePlace(loc: Location, emit: (Map<String, Any?>) -> Unit) {
        val out = HashMap<String, Any?>()
        out["lat"] = loc.latitude
        out["lng"] = loc.longitude
        out["accuracy"] = loc.accuracy.toDouble()
        out["ageMs"] = (System.currentTimeMillis() - loc.time).coerceAtLeast(0L)

        if (!Geocoder.isPresent()) {
            emit(out)
            return
        }
        Thread {
            val latch = java.util.concurrent.CountDownLatch(1)
            var province = ""
            var city = ""
            Thread {
                try {
                    @Suppress("DEPRECATION")
                    val list = Geocoder(activity, Locale.CHINA)
                        .getFromLocation(loc.latitude, loc.longitude, 1)
                    val place = list?.firstOrNull()
                    if (place != null) {
                        province = place.adminArea.orEmpty()
                        city = place.locality.orEmpty().ifEmpty { place.subAdminArea.orEmpty() }
                    }
                } catch (_: Throwable) {
                } finally {
                    latch.countDown()
                }
            }.start()
            try {
                latch.await(1500, java.util.concurrent.TimeUnit.MILLISECONDS)
            } catch (_: Throwable) {
            }
            val finalProvince = province
            val finalCity = city
            main.post {
                if (finalProvince.isNotEmpty()) out["province"] = finalProvince
                if (finalCity.isNotEmpty()) out["city"] = finalCity
                emit(out)
            }
        }.start()
    }

    // ------------------------------------------------------------ 蜂窝状态回调

    private fun registerTelephony() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val tm = telephony() ?: return
        try {
            val cb = object : TelephonyCallback(),
                TelephonyCallback.DisplayInfoListener,
                TelephonyCallback.PhysicalChannelConfigListener {

                override fun onDisplayInfoChanged(info: TelephonyDisplayInfo) {
                    overrideNetworkType = info.overrideNetworkType
                    displayNetworkType = info.networkType
                }

                override fun onPhysicalChannelConfigChanged(configs: MutableList<PhysicalChannelConfig>) {
                    val serving = configs.firstOrNull {
                        it.connectionStatus == PhysicalChannelConfig.CONNECTION_PRIMARY_SERVING
                    } ?: configs.firstOrNull() ?: return
                    pcBandwidthKhz = serving.cellBandwidthDownlinkKhz
                    pcIsNr = serving.networkType == TelephonyManager.NETWORK_TYPE_NR
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        pcBand = try {
                            serving.band
                        } catch (_: Throwable) {
                            0
                        }
                    }
                }
            }
            tm.registerTelephonyCallback(activity.mainExecutor, cb)
            telephonyCallback = cb
            displayNetworkType = try {
                tm.dataNetworkType
            } catch (_: Throwable) {
                0
            }
        } catch (_: Throwable) {
        }
    }

    private fun unregisterTelephony() {
        val cb = telephonyCallback ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                telephony()?.unregisterTelephonyCallback(cb as TelephonyCallback)
            } catch (_: Throwable) {
            }
        }
        telephonyCallback = null
        overrideNetworkType = 0
        displayNetworkType = 0
        pcBandwidthKhz = 0
        pcBand = 0
        pcIsNr = false
    }
}
