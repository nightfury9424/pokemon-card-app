package com.fury.pokemoncardapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // FCM notification payload 가 게시될 high-importance 채널.
        // 서버(FcmService)는 채널 ID 를 지정하지 않으므로 manifest 의
        // default_notification_channel_id(pokefolio_default)가 사용된다 — 여기서 그 채널을
        // 실제로 만들어 둔다(채널이 없으면 FCM 이 저중요도 fallback 채널로 게시).
        // 새 Flutter 패키지 없이 네이티브 몇 줄로 해결(심사 직전 의존성 추가 회피 — 오너 결정).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "pokefolio_default",
                "알림",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "거래·채팅·공지 알림" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
