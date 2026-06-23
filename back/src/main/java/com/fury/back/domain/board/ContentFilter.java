package com.fury.back.domain.board;

import jakarta.annotation.PostConstruct;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/**
 * 게시판 본문/댓글 금칙어 검증.
 *
 * <p>NicknameValidator 의 **banned-word 목록만** 재사용(reserved/impersonation 등 닉네임 전용
 * 정책은 제외 — 게시글에는 부적절). resources/banned/banned_words.txt 를 부팅 1회 로드.
 */
@Component
public class ContentFilter {

    private Set<String> bannedWords = Set.of();

    @PostConstruct
    void load() {
        bannedWords = loadLines("banned/banned_words.txt");
    }

    private Set<String> loadLines(String path) {
        Set<String> out = new HashSet<>();
        ClassPathResource res = new ClassPathResource(path);
        if (!res.exists()) return out;
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(res.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                String w = line.trim().toLowerCase(Locale.ROOT);
                if (!w.isEmpty() && !w.startsWith("#")) out.add(w);
            }
        } catch (Exception ignored) {
            // 로드 실패 시 빈 셋(차단 안 함) — 부팅 막지 않음. 운영 모니터링 별도.
        }
        return out;
    }

    /** text 에 금칙어가 포함되면 true. */
    public boolean containsBanned(String text) {
        if (text == null || text.isEmpty() || bannedWords.isEmpty()) return false;
        String lower = text.toLowerCase(Locale.ROOT);
        for (String bad : bannedWords) {
            if (lower.contains(bad)) return true;
        }
        return false;
    }
}
