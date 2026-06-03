import Flutter
import UIKit
import FirebaseAuth

class SceneDelegate: FlutterSceneDelegate {

  // UIScene 라이프사이클에선 URL open 이 AppDelegate.application(_:open:) 대신 여기로 들어온다.
  // Phone Auth reCAPTCHA fallback 콜백을 Auth 가 먼저 처리하고, 아니면 super 로 위임해
  // Flutter 플러그인(Google Sign-In 등) URL 핸들링을 보존한다.
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    for ctx in URLContexts {
      if Auth.auth().canHandle(ctx.url) { return }
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
