package com.fury.back.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class SwaggerConfig {

    @Bean
    public OpenAPI openAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("포켓몬 카드 앱 API")
                        .description("""
                                포켓몬 카드 스캔·시세·자산 관리 서비스 API 문서

                                **1차 기능**
                                - 카드 스캔 및 식별
                                - 카드 상세 조회 및 검색
                                - 시세 조회 (당근/번개장터/icu.gg 기반)
                                - 자산 등록·수정·삭제
                                - 포트폴리오 요약

                                **카드 상태 분류**
                                - `RAW`: 일반 카드
                                - `GRADED`: PSA / BGS / CGC 등 그레이딩 카드
                                """)
                        .version("v1.0")
                        .contact(new Contact().name("pokemon-card-app")));
    }
}
