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
    // SceneDelegate 환경에서 swizzling 타이밍에 의존하지 않도록 명시적으로 APNs 등록.
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNs 토큰을 Firebase Messaging 에 명시적으로 전달 (SceneDelegate swizzling 보강).
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    // Firebase Phone Auth 도 APNs 토큰 필요 — verifyPhoneNumber 의 silent push 앱 검증용.
    // 누락 시 reCAPTCHA fallback 으로 빠지고, URL scheme 불일치로 native assertion 크래시 발생.
    // .unknown 자동판별이 TestFlight(prod APNs)에서 silent push 실패 유발 → 환경 명시.
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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
