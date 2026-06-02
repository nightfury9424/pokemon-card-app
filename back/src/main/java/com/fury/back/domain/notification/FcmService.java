package com.fury.back.domain.notification;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.io.FileInputStream;
import java.util.Map;

/**
 * FCM 기기 푸시 전송. service-account.json 으로 Firebase Admin 초기화.
 *   firebase.service-account-path 미설정 시 → messaging=null → sendToUser no-op
 *   (in-app Notification 은 NotificationService 가 별도 저장하므로 푸시만 skip).
 * 자격증명(.json) 받으면 .env.prod 에 FIREBASE_SERVICE_ACCOUNT_PATH 만 지정하면 활성화.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FcmService {

    private final FcmTokenRepository fcmTokenRepository;

    @Value("${firebase.service-account-path:}")
    private String serviceAccountPath;

    private FirebaseMessaging messaging;

    @PostConstruct
    void init() {
        if (serviceAccountPath == null || serviceAccountPath.isBlank()) {
            log.warn("[FCM] firebase.service-account-path 미설정 — 푸시 비활성(no-op).");
            return;
        }
        try (FileInputStream sa = new FileInputStream(serviceAccountPath)) {
            FirebaseOptions options = FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(sa))
                    .build();
            FirebaseApp app = FirebaseApp.getApps().isEmpty()
                    ? FirebaseApp.initializeApp(options)
                    : FirebaseApp.getInstance();
            this.messaging = FirebaseMessaging.getInstance(app);
            log.info("[FCM] Firebase Admin 초기화 완료.");
        } catch (Exception e) {
            log.error("[FCM] 초기화 실패 — 푸시 비활성: {}", e.getMessage());
        }
    }

    /** userId 의 모든 등록 기기에 푸시. 미설정/오류는 조용히 skip. @Async — 채팅/거래 흐름 비차단. */
    @Async
    public void sendToUser(String userId, String title, String body, Map<String, String> data) {
        if (messaging == null) return;
        for (FcmToken t : fcmTokenRepository.findByUserId(userId)) {
            try {
                messaging.send(Message.builder()
                        .setToken(t.getToken())
                        .setNotification(com.google.firebase.messaging.Notification.builder()
                                .setTitle(title)
                                .setBody(body)
                                .build())
                        .putAllData(data != null ? data : Map.of())
                        .build());
            } catch (Exception e) {
                log.warn("[FCM] 전송 실패 token={}: {}", t.getTokenId(), e.getMessage());
            }
        }
    }
}
