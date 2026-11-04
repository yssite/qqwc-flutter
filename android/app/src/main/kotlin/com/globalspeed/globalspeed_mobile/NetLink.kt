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
import android.telephony.CellInfo
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

    /**
     * 当前承载数据的 subscriptionId。
     *
     * 分层判断，避免任何单一 API 在某些 ROM 上「永远是同一张卡」：
     * 1. 当前活动网络自己声明的 subId 集合（`NetworkCapabilities.getSubscriptionIds()`）；
     * 2. 系统默认数据卡 —— 但必须验证它真的连着数据；
     * 3. 遍历活动卡，挑 `dataState` 已连接 / 上报了数据制式的那张；
     * 4. 都不行才退回默认值。
     */
    @SuppressLint("MissingPermission")
    private fun activeDataSubId(): Int {
        val candidates = ArrayList<Int>()
        try {
            val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (cm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val caps = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) }
                caps?.subscriptionIds?.forEach { if (it >= 0) candidates.add(it) }
            }
        } catch (_: Throwable) {
        }
        if (candidates.size == 1) return candidates[0]
        if (candidates.size > 1) {
            return candidates.firstOrNull { hasDataOn(it) } ?: candidates[0]
        }

        val def = try {
            SubscriptionManager.getDefaultDataSubscriptionId()
        } catch (_: Throwable) {
            SubscriptionManager.DEFAULT_SUBSCRIPTION_ID
        }
        // 默认数据卡只有在「确实连着数据」时才采信，否则继续往下扫
        if (def >= 0 && dataConnected(def)) return def

        val actives = try {
            val sm = activity.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? SubscriptionManager
            sm?.activeSubscriptionInfoList?.map { it.subscriptionId } ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
        actives.firstOrNull { dataConnected(it) }?.let { return it }
        actives.firstOrNull { hasDataOn(it) }?.let { return it }
        return def
    }

    /** 该卡是否处于「数据已连接」状态（DSDS 下只有数据卡成立）。 */
    @SuppressLint("MissingPermission")
    private fun dataConnected(subId: Int): Boolean {
        if (subId < 0) return false
        val base = activity.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return false
        return try {
            base.createForSubscriptionId(subId).dataState == TelephonyManager.DATA_CONNECTED
        } catch (_: Throwable) {
            false
        }
    }

    /** 宽松判断：有数据连接或上报了数据制式。 */
    @SuppressLint("MissingPermission")
    private fun hasDataOn(subId: Int): Boolean {
        if (subId < 0) return false
        val base = activity.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return false
        return try {
            val tm = base.createForSubscriptionId(subId)
            tm.dataState == TelephonyManager.DATA_CONNECTED ||
                tm.dataNetworkType != TelephonyManager.NETWORK_TYPE_UNKNOWN
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * 绑定到数据卡的 TelephonyManager。
     * 双卡机型切卡后如果不按 subId 取实例，拿到的永远是默认（第一张）卡的信息。
     */
    private fun telephony(): TelephonyManager? {
        val base = activity.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return null
        val subId = activeDataSubId()
        if (subId < 0) return base
        return try {
            base.createForSubscriptionId(subId)
        } catch (_: Throwable) {
            base
        }
    }

    /**
     * 数据卡变了、或上次注册失败（例如启动时还没授权）就重新注册回调。
     * 这一步是关键：注册失败必须能把状态清空，否则永远拿不到 DisplayInfo / PhysicalChannelConfig。
     */
    private fun ensureTelephony() {
        val subId = activeDataSubId()
        val needRegister = telephonyCallback == null || subId != registeredSubId
        if (!needRegister) return
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
            "debug" -> result.success(debugInfo())
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
        val subId = activeDataSubId()
        out["subId"] = subId
        out["simSlot"] = try {
            if (subId >= 0) SubscriptionManager.getSlotIndex(subId) else -1
        } catch (_: Throwable) {
            -1
        }
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

        // 只认数据卡所在的那张网。
        // 注意：部分 ROM（如 MIUI）的 allCellInfo 会把两张卡的小区一起返回，
        // 因此这里绝不允许「匹配不到就退回全部小区」—— 宁可只显示制式，也不能冒用另一张卡的数据。
        val plmn = normalizePlmn(
            try {
                tm.networkOperator.orEmpty()
            } catch (_: Throwable) {
                ""
            },
        )
        out["plmn"] = plmn
        val registered = cells.filter { it.isRegistered }
        val ownCells = registered.filter { matchCell(it, plmn) != "none" }
        out["cellCount"] = cells.size
        out["ownCellCount"] = ownCells.size
        out["cellMatch"] = registered.firstOrNull()?.let { matchCell(it, plmn) } ?: "none"
        if (ownCells.isEmpty()) {
            // 仍然记录一下每个小区归属，方便日志排查
            out["cellsSeen"] = registered.map { cellPlmns(it) }
            return out
        }

        val target = ownCells.firstOrNull {
            if (nr) it is CellInfoNr else it is CellInfoLte
        } ?: ownCells.firstOrNull()

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

    // ------------------------------------------------------------ 双卡诊断

    /** MCC+MNC 归一化：不同卡上报的 MNC 可能是 2 位或 3 位，比较前 5 位即可。 */
    private fun normalizePlmn(raw: String): String =
        raw.filter { it.isDigit() }.take(5)

    private fun cellPlmn(ci: CellInfo): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return ""
        return try {
            when (ci) {
                is CellInfoNr -> {
                    val id = ci.cellIdentity as? CellIdentityNr
                    if (id == null) "" else "${id.mccString.orEmpty()}${id.mncString.orEmpty()}"
                }
                is CellInfoLte -> {
                    val id = ci.cellIdentity as? CellIdentityLte
                    if (id == null) "" else "${id.mccString.orEmpty()}${id.mncString.orEmpty()}"
                }
                else -> ""
            }
        } catch (_: Throwable) {
            ""
        }
    }

    /** 小区广播的全部 PLMN（主 PLMN + MOCN 共建共享的 additional PLMN）。 */
    private fun cellPlmns(ci: CellInfo): List<String> {
        val list = ArrayList<String>()
        val primary = normalizePlmn(cellPlmn(ci))
        if (primary.isNotEmpty()) list.add(primary)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return list
        try {
            val extra = when (ci) {
                is CellInfoNr -> (ci.cellIdentity as? CellIdentityNr)?.additionalPlmns
                is CellInfoLte -> (ci.cellIdentity as? CellIdentityLte)?.additionalPlmns
                else -> null
            }
            extra?.forEach { raw ->
                val p = normalizePlmn(raw)
                if (p.isNotEmpty() && !list.contains(p)) list.add(p)
            }
        } catch (_: Throwable) {
        }
        return list
    }

    /**
     * 中国共建共享的运营商对：
     * - 联通 46001 ↔ 电信 46011（5G 共建共享，同一基站可广播两个 PLMN）
     * - 移动 46000 ↔ 广电 46015（700MHz 共享）
     * 卡挂在对方基站上时，小区 PLMN 可能与核心网 PLMN 不同，但流量仍走自己核心网。
     */
    private fun sharedPartner(plmn: String): List<String> = when (plmn) {
        "46001" -> listOf("46011")
        "46011" -> listOf("46001")
        "46000" -> listOf("46015", "46020")
        "46015", "46020" -> listOf("46000")
        else -> emptyList()
    }

    /** 该小区是否属于数据卡所在的网络：主 PLMN → 额外 PLMN → 共建共享对。 */
    private fun matchCell(ci: CellInfo, dataPlmn: String): String {
        if (dataPlmn.isEmpty()) return "unknown"
        val plmns = cellPlmns(ci)
        if (plmns.isEmpty()) return "unknown"
        if (plmns.firstOrNull() == dataPlmn) return "plmn"
        if (plmns.drop(1).contains(dataPlmn)) return "additional"
        val partners = sharedPartner(dataPlmn)
        if (plmns.any { partners.contains(it) }) return "shared"
        return "none"
    }

    /**
     * 详细诊断快照：双卡相关的一切都列出来，配套 App 的「详细日志」导出用。
     */
    @SuppressLint("MissingPermission")
    private fun debugInfo(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["build"] = mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "sdk" to Build.VERSION.SDK_INT,
            "release" to Build.VERSION.RELEASE,
        )
        out["defaultDataSubId"] = try {
            SubscriptionManager.getDefaultDataSubscriptionId()
        } catch (_: Throwable) {
            -1
        }
        out["defaultSubId"] = try {
            SubscriptionManager.getDefaultSubscriptionId()
        } catch (_: Throwable) {
            -1
        }
        out["activeDataSubId"] = try {
            activeDataSubId()
        } catch (_: Throwable) {
            -1
        }
        out["registeredSubId"] = registeredSubId

        val subs = ArrayList<Map<String, Any?>>()
        try {
            val sm = activity.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? SubscriptionManager
            sm?.activeSubscriptionInfoList?.forEach { info ->
                subs.add(
                    mapOf(
                        "subId" to info.subscriptionId,
                        "slot" to info.simSlotIndex,
                        "carrier" to info.carrierName?.toString().orEmpty(),
                        "display" to info.displayName?.toString().orEmpty(),
                    ),
                )
            }
        } catch (_: Throwable) {
        }
        out["subscriptions"] = subs

        val tm = telephony()
        if (tm != null) {
            out["simOperator"] = try {
                tm.simOperator
            } catch (_: Throwable) {
                ""
            }
            out["simOperatorName"] = try {
                tm.simOperatorName
            } catch (_: Throwable) {
                ""
            }
            out["networkOperator"] = try {
                tm.networkOperator
            } catch (_: Throwable) {
                ""
            }
            out["networkOperatorName"] = try {
                tm.networkOperatorName
            } catch (_: Throwable) {
                ""
            }
            out["dataNetworkType"] = try {
                tm.dataNetworkType
            } catch (_: Throwable) {
                -1
            }
            val cells = ArrayList<Map<String, Any?>>()
            try {
                tm.allCellInfo?.forEach { ci ->
                    cells.add(
                        mapOf(
                            "type" to when (ci) {
                                is CellInfoNr -> "nr"
                                is CellInfoLte -> "lte"
                                else -> "other"
                            },
                            "registered" to ci.isRegistered,
                            "plmn" to cellPlmn(ci),
                            "level" to ci.cellSignalStrength.level,
                        ),
                    )
                }
            } catch (_: Throwable) {
            }
            out["cells"] = cells
        }
        out["pc"] = mapOf(
            "bandwidthKhz" to pcBandwidthKhz,
            "band" to pcBand,
            "isNr" to pcIsNr,
            "override" to overrideNetworkType,
            "displayType" to displayNetworkType,
        )
        out["transport"] = try {
            val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            cm?.getNetworkCapabilities(cm.activeNetwork)?.transportInfo?.toString().orEmpty()
        } catch (_: Throwable) {
            ""
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

    @SuppressLint("MissingPermission")
    private fun registerTelephony() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        // 这两个回调都需要 READ_PHONE_STATE；没授权就别注册，等下次快照再试
        if (!granted(Manifest.permission.READ_PHONE_STATE)) return
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
            // 注册失败：保持 telephonyCallback 为 null，ensureTelephony() 下次会重试
            telephonyCallback = null
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
