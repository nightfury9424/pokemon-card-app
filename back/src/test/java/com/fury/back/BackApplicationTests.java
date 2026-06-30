package com.fury.back;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

// 컨텍스트 부팅 검증은 격리 프로파일(citest: 더미 config + create-drop, pokefolio_ci)에서 수행.
// 환경변수 없이 ./gradlew test 가 개발자 로컬 DB(pokemon_card_db)에 validate 하지 않도록 격리.
// (board repository 테스트는 각자 @ActiveProfiles("boardtest")로 validate+실마이그 검증 유지.)
@SpringBootTest
@ActiveProfiles("citest")
class BackApplicationTests {

    @Test
    void contextLoads() {
    }

}
