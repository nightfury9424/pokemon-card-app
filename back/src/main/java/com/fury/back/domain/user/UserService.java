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

        // 3. PII 마스킹 + deletedAt 설정
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
