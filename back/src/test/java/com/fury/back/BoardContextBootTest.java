package com.fury.back;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * 전체 애플리케이션 컨텍스트 부팅 검증(배포 동등 격리 DB, 더미 config).
 *
 * <p>게시판 쓰기 슬라이스 추가분(컨트롤러/서비스/엔티티 + AdminAuthorizationService)을 포함한
 * **전체 빈 그래프가 정상 wiring + 스키마 매핑** 되는지 증명. ddl-auto=create-drop 로 엔티티에서
 * 스키마를 생성하므로 로컬 dev DB drift(buy_orders 등, board 무관)와 무관하게 부팅한다.
 *
 * <p>기존 {@code BackApplicationTests}(default 프로필)는 실제 배포 시크릿 env 부재로 이 로컬에서
 * 부팅 불가 → 본 테스트가 동등한 전체 부팅 보증을 대체 제공.
 */
@SpringBootTest
@ActiveProfiles("citest")
class BoardContextBootTest {

    @Test
    void contextLoads() {
    }
}
