package com.globalspeed.globalspeed_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var netLink: NetLink? = null
    private var updater: Updater? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        netLink = NetLink(this).also { it.attach(messenger) }
        updater = Updater(this).also { it.attach(messenger) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        netLink?.onPermissionResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        netLink?.detach()
        netLink = null
        updater?.detach()
        updater = null
        super.onDestroy()
    }
}
