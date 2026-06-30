package app.yarmy.mobile_yarmy

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode

class MainActivity : FlutterActivity() {
    override fun getRenderMode(): RenderMode {
        val isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        // The Android emulator can keep the starting splash above Flutter's SurfaceView.
        // TextureView is a little slower, so keep it limited to debuggable builds.
        return if (isDebuggable) RenderMode.texture else super.getRenderMode()
    }
}
