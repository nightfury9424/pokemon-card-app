import Flutter
import UIKit
import Firebase
import FirebaseMessaging
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Firebase 는 다른 Firebase 호출 전에 반드시 먼저 설정.
    FirebaseApp.configure()
    // ★ Flutter 3.41 UIScene/implicit-engine 회피 (flutter/flutter#185048):
    // 새 implicit engine(didInitializeImplicitFlutterEngine) 로만 등록하면 Firebase 플러그인이
    // app delegate(addApplicationDelegate)에 안 붙어 remote notification 이 Auth/Messaging 으로
    // forwarding 안 됨 → notification-not-forwarded. UIScene 매니페스트 제거 + classic lifecycle
    // 회귀 + self 단일 등록으로 해결(둘 다 등록하면 plugin already-registered 로 abort).
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // proxy ON 이면 swizzling 이 토큰을 자동 forward 하지만, Auth 앱검증 토큰을 보장하기 위한
  // insurance 로 명시 set. .unknown → Firebase 가 entitlement 기준 sandbox/prod 자동 감지.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
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
}
