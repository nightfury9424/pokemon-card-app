package com.fury.back.domain.user;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.trade.BuyOrder;
import com.fury.back.domain.trade.BuyOrderRepository;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * User 도메인 application 서비스. UserController가 기존엔 UserRepository만 쓰지만,
 * 탈퇴(P0-A, App Review 5.1.1 대응) 로직은 여러 entity 트랜잭션이라 별도 서비스로 분리.
 *
 * 탈퇴 정책 (docs/DELETION_POLICY.md 단일 진실원):
 *  - users: nickname/email/profileImageUrl 마스킹 + deletedAt 설정. googleId 유지(재로그인 감지용).
 *  - buy_orders OPEN: 자동 CANCELED. MATCHED는 보존(이력).
 *  - trade_posts OPEN/RESERVED: 자동 DELETED. COMPLETED는 보존(이력).
 *  - chat_messages / chat_rooms / reports / blocks: 보존 (분쟁·운영 증거).
 *  - card_interests / post_interests / notifications / assets: 이번 P0-A 범위에선 보존
 *    (다음 commit 또는 v1.1에서 hard delete 정책 추가 가능). 현재는 응답 DTO가 nickname 마스킹된 user
 *    를 참조하므로 노출엔 문제 없음.
 *
 * 인증: userId는 controller의 @AuthenticationPrincipal에서 받음. param/body로 받지 않음(보안).
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final BuyOrderRepository buyOrderRepository;
    private final TradePostRepository tradePostRepository;
    private final PhoneVerifyAttemptRepository phoneVerifyAttemptRepository;
    private final DeletedUserAuditRepository deletedUserAuditRepository;

    /** 탈퇴 후 원본 PII 보존 기간(일). 전자상거래법 §6 거래기록 3개월 보존 기준. 경과 시 purge cron이 완전 삭제. */
    private static final int DELETION_RETENTION_DAYS = 90;

    // 휴대폰 OTP 발송 strict 가드 — Firebase quota 보강(우리 측 영속 추적).
    private static final int OTP_COOLDOWN_SECONDS = 60;
    private static final int OTP_MAX_PER_PHONE_DAY = 5;
    // 한국 통신사 CGNAT(다수 유저가 공인 IP 공유) 고려 — 15는 정상 유저 오차단 위험.
    // per-phone(5)가 실 SMS 비용 게이트, per-IP 는 단일 IP 대량 abuse 방지 천장으로만 사용.
    private static final int OTP_MAX_PER_IP_DAY = 100;
    private static final int OTP_MAX_PER_USER_DAY = 5;

    @Transactional
    public ReturnData<Map<String, Object>> deleteAccount(String userId) {
        if (userId == null || userId.isBlank()) {
            return ReturnData.fail("F403", "인증이 필요합니다.");
        }
        User user = userRepository.findById(userId).orElse(null);
        if (user == null) {
            return ReturnData.notFound("사용자를 찾을 수 없습니다.");
        }
        if (user.getDeletedAt() != null) {
            return ReturnData.badRequest("이미 탈퇴한 계정입니다.");
        }

        // 1. 활성 매수 호가 자동 취소 (OPEN → CANCELED). MATCHED는 그대로 (이력).
        List<BuyOrder> openOrders = buyOrderRepository
                .findByBuyerIdAndStatusOrderByCreatedAtDesc(userId, "OPEN");
        for (BuyOrder order : openOrders) {
            order.updateStatus("CANCELED");
        }

        // 2. 활성 판매글 자동 삭제 (OPEN/RESERVED → DELETED). COMPLETED는 그대로 (거래 기록).
        List<TradePost> openTrades = tradePostRepository
                .findBySellerIdAndStatusIn(userId, List.of("OPEN", "RESERVED"));
        for (TradePost post : openTrades) {
            post.markDeleted();
        }

        // 3. 원본 PII를 admin audit에 보관 (★마스킹 전!) — 분쟁/사기 대응 90일 보존 후 purge cron이 완전삭제.
        //    동일 @Transactional — audit 저장 실패 시 마스킹도 롤백(원본 보존 없이 탈퇴되는 일 방지).
        deletedUserAuditRepository.save(
                DeletedUserAudit.capture(user, LocalDateTime.now(), DELETION_RETENTION_DAYS));

        // 4. PII 마스킹 + deletedAt 설정
        String maskedNickname = "탈퇴한 사용자 #" + computeShortHash(userId);
        user.markDeletedAndMask(maskedNickname);
        userRepository.save(user);

        log.info("[UserDeletion] user={} masked_nickname={} cancelled_orders={} deleted_trades={}",
                userId, maskedNickname, openOrders.size(), openTrades.size());

        return ReturnData.success(Map.of(
                "deletedAt", user.getDeletedAt().toString(),
                "cancelledOrders", openOrders.size(),
                "deletedTrades", openTrades.size()
        ));
    }

    /**
     * 휴대폰 OTP 인증 — Flutter 가 Firebase Phone Auth 로 받은 ID 토큰 검증 후 사용자에 phone 저장.
     * firebase-admin(FcmService 가 초기화한 default app) 으로 verifyIdToken → phone_number claim 추출.
     * 번호당 인증계정 1개(중복 명의 차단). 로드된 엔티티 직접 변경(merge null 버그 회피).
     */
    @Transactional
    public ReturnData<Map<String, Object>> verifyPhone(String userId, String firebaseIdToken) {
        if (userId == null || userId.isBlank()) {
            return ReturnData.fail("F403", "인증이 필요합니다.");
        }
        if (firebaseIdToken == null || firebaseIdToken.isBlank()) {
            return ReturnData.badRequest("firebaseIdToken 이 필요합니다.");
        }
        String phoneE164;
        try {
            com.google.firebase.auth.FirebaseToken decoded =
                    com.google.firebase.auth.FirebaseAuth.getInstance().verifyIdToken(firebaseIdToken);
            Object phone = decoded.getClaims().get("phone_number");
            phoneE164 = phone == null ? null : phone.toString().trim();
        } catch (Exception e) {
            log.warn("[Phone] Firebase ID 토큰 검증 실패: {}", e.getMessage());
            return ReturnData.fail("F_PHONE_TOKEN", "휴대폰 인증 검증에 실패했습니다. 다시 시도해주세요.");
        }
        if (phoneE164 == null || phoneE164.isBlank()) {
            return ReturnData.fail("F_PHONE_TOKEN", "휴대폰 번호 정보를 확인할 수 없습니다.");
        }
        if (!phoneE164.startsWith("+82")) {
            return ReturnData.fail("F_PHONE_KR", "한국 휴대폰 번호만 인증할 수 있어요.");
        }
        // 번호당 인증계정 1개 — 본인 외 다른 계정이 이미 인증했으면 차단.
        var existing = userRepository.findByPhoneE164AndPhoneVerifiedTrue(phoneE164);
        if (existing.isPresent() && !existing.get().getUserId().equals(userId)) {
            return ReturnData.fail("F_PHONE_DUP", "이미 다른 계정에서 인증된 번호입니다.");
        }
        User user = userRepository.findById(userId).orElse(null);
        if (user == null) {
            return ReturnData.notFound("사용자를 찾을 수 없습니다.");
        }
        user.verifyPhone(phoneE164);
        userRepository.save(user);
        log.info("[Phone] user={} 휴대폰 인증 완료", userId);
        return ReturnData.success(Map.of("phoneVerified", true, "phoneE164", phoneE164));
    }

    /**
     * OTP 발송 전 strict 가드 — 클라가 Firebase verifyPhoneNumber 호출 전에 먼저 호출.
     * 휴대폰/IP/계정별 횟수+쿨타임을 DB(영속)로 차단. 통과 시에만 클라가 발송 진행.
     * (앱 밖 우회는 Firebase quota + App Check 가 보강.)
     */
    @Transactional
    public ReturnData<Map<String, Object>> requestOtp(String userId, String phone, String ip) {
        if (userId == null || userId.isBlank()) {
            return ReturnData.fail("F403", "인증이 필요합니다.");
        }
        String e164 = normalizeKr(phone);
        if (e164 == null) {
            return ReturnData.fail("F_PHONE_KR", "올바른 한국 휴대폰 번호를 입력해주세요.");
        }
        java.time.LocalDateTime now = java.time.LocalDateTime.now();
        if (phoneVerifyAttemptRepository.countByPhoneE164AndCreatedAtAfter(e164, now.minusSeconds(OTP_COOLDOWN_SECONDS)) >= 1) {
            return ReturnData.fail("F_PHONE_COOLDOWN", "잠시 후 다시 시도해주세요.");
        }
        if (phoneVerifyAttemptRepository.countByPhoneE164AndCreatedAtAfter(e164, now.minusDays(1)) >= OTP_MAX_PER_PHONE_DAY) {
            return ReturnData.fail("F_PHONE_LIMIT", "이 번호의 오늘 인증 가능 횟수를 초과했어요.");
        }
        if (ip != null && !ip.isBlank()
                && phoneVerifyAttemptRepository.countByIpAndCreatedAtAfter(ip, now.minusDays(1)) >= OTP_MAX_PER_IP_DAY) {
            return ReturnData.fail("F_PHONE_LIMIT", "요청이 많아 잠시 후 다시 시도해주세요.");
        }
        if (phoneVerifyAttemptRepository.countByUserIdAndCreatedAtAfter(userId, now.minusDays(1)) >= OTP_MAX_PER_USER_DAY) {
            return ReturnData.fail("F_PHONE_LIMIT", "오늘 인증 가능 횟수를 초과했어요.");
        }
        phoneVerifyAttemptRepository.save(PhoneVerifyAttempt.builder()
                .attemptId(com.fury.back.common.IdGenerator.generate())
                .phoneE164(e164).userId(userId).ip(ip).build());
        return ReturnData.success(Map.of("allowed", true, "phoneE164", e164));
    }

    /** 한국 휴대폰만 → +82 E.164. 형식 안 맞으면 null. */
    private String normalizeKr(String raw) {
        if (raw == null) return null;
        String d = raw.replaceAll("[^0-9]", "");
        if (d.startsWith("82")) d = "0" + d.substring(2);
        if (!d.matches("^01[016789]\\d{7,8}$")) return null;
        return "+82" + d.substring(1);
    }

    /** userId → SHA-256[0:3] = 6 hex chars uppercase. 비가역, 짧고 같은 userId면 항상 같은 값. */
    private String computeShortHash(String userId) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] hash = md.digest(userId.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 3; i++) sb.append(String.format("%02X", hash[i]));
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            // SHA-256는 표준 — 거의 안 일어남. fallback.
            return Integer.toHexString(userId.hashCode() & 0xFFFFFF).toUpperCase();
        }
    }
}
