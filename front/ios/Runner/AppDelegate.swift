import Flutter
import UIKit
import Firebase
import FirebaseMessaging
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Firebase 는 다른 Firebase 호출 전에 반드시 먼저 설정.
    FirebaseApp.configure()
    // FirebaseAppDelegateProxyEnabled=NO (proxy/swizzling 비활성) — 알림 수동 배선.
    // proxy 가 UNUserNotificationCenter delegate 를 안 잡아주므로 명시 set →
    // FlutterAppDelegate 가 willPresent/didReceive 를 등록 플러그인(FCM)으로 forward.
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNs 토큰을 Firebase Messaging 에 명시적으로 전달 (SceneDelegate swizzling 보강).
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    // Phone Auth silent push 앱검증용 APNs 토큰. ★UIBackgroundModes:remote-notification 추가로
    // content-available silent push 가 didReceiveRemoteNotification 에 전달됨 → canHandleNotification.
    #if DEBUG
    Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
    #else
    Auth.auth().setAPNSToken(deviceToken, type: .prod)
    #endif
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Phone Auth 의 silent 검증 push 를 Auth 가 먼저 가로채도록 — FCM 플러그인이 먼저 삼키면
  // 앱 검증이 실패해 reCAPTCHA fallback→(잘못된 URL scheme)→크래시. Auth push 가 아니면 super 로 위임.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if Auth.auth().canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[FCM] APNs 등록 실패: \(error)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // reCAPTCHA(Phone Auth) / OAuth callback URL — proxy 비활성 시 Auth 로 수동 전달.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if Auth.auth().canHandle(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
