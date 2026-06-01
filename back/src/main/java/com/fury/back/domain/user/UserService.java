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
