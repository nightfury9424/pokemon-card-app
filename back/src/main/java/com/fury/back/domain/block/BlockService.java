package com.fury.back.domain.block;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.chat.ChatService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * 차단 공통 처리. 모든 진입점(사용자/게시글/댓글)이 이 서비스를 호출한다.
 * ★쓰기 트랜잭션 경계를 여기에 둔다 — insertIgnoreBlock 은 @Modifying 네이티브 쿼리라 반드시 트랜잭션이 필요.
 * Controller 메서드의 @Transactional 에 의존하지 않게 서비스 계층으로 일원화.
 */
@Service
@RequiredArgsConstructor
public class BlockService {

    private final BlockRepository blockRepository;
    private final ChatService chatService;

    /** 차단 결과 — blockId + 신규 생성 여부(201/200 구분용). */
    public record BlockResult(String blockId, boolean created) {}

    /**
     * self/blank 거부 + 멱등(ON CONFLICT DO NOTHING, 동시 요청에도 unique 위반 없이 1행) + 신규일 때만 notifyBlock.
     */
    @Transactional
    public BlockResult block(String blockerId, String blockedId) {
        if (blockedId == null || blockedId.isBlank() || blockerId.equals(blockedId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "SELF_BLOCK");
        }
        String newId = IdGenerator.generate();
        boolean created = blockRepository.insertIgnoreBlock(newId, blockerId, blockedId) > 0;
        // Phase 1: 차단한 사람 hidden_at set + 차단당한 사람 방에 SYSTEM 메시지 1회. 신규일 때만(중복 알림 방지).
        // board 작성자처럼 채팅방이 없으면 no-op.
        if (created) {
            chatService.notifyBlock(blockerId, blockedId);
        }
        String blockId = created ? newId
                : blockRepository.findByBlockerIdAndBlockedId(blockerId, blockedId)
                        .map(Block::getBlockId).orElse(newId);
        return new BlockResult(blockId, created);
    }
}
