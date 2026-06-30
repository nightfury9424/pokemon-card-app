package com.fury.back.domain.block;

import com.fury.back.BackApplication;
import com.fury.back.domain.chat.ChatService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * BlockService 트랜잭션 경계 검증 — ★클래스 @Transactional 없음(테스트 트랜잭션이 결함을 가리지 않게).
 * insertIgnoreBlock 은 @Modifying 네이티브 쿼리 → BlockService.block 의 @Transactional 이 없으면 운영에서 실패.
 * 테스트 트랜잭션 밖에서 호출했는데 행이 커밋되어 보인다 = 서비스 자체 트랜잭션이 동작함을 증명. 커밋되므로 @AfterEach 정리.
 */
@SpringBootTest(classes = BackApplication.class)
@ActiveProfiles("citest")
class BlockServiceTxTest {

    @Autowired BlockService blockService;
    @Autowired BlockRepository blockRepository;
    @MockitoBean ChatService chatService;

    @AfterEach
    void cleanup() {
        blockRepository.deleteAll(); // 커밋된 행 정리(이 테스트만 비-tx → 누수 방지)
    }

    @Test
    void block_commitsInOwnTransaction_outsideTestTx() {
        var r = blockService.block("txBlocker", "txBlocked");
        assertThat(r.created()).isTrue();
        // 테스트 tx 가 없으므로 이 조회가 보인다 = BlockService.block 의 @Transactional 이 @Modifying 삽입을 커밋함.
        assertThat(blockRepository.existsByBlockerIdAndBlockedId("txBlocker", "txBlocked")).isTrue();
    }

    @Test
    void block_repeated_isIdempotent_committed() {
        blockService.block("txBlocker", "txBlocked");
        var second = blockService.block("txBlocker", "txBlocked");
        assertThat(second.created()).isFalse(); // 두 번째는 ON CONFLICT → 기존 반환
        assertThat(blockRepository.findAllByBlockerId("txBlocker")).hasSize(1);
    }
}
