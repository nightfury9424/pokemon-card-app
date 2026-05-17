package com.fury.back.domain.user;

import jakarta.annotation.PostConstruct;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.text.BreakIterator;
import java.text.Normalizer;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * 닉네임 정규화/검증.
 *
 * 정책:
 *  - 입력은 NFKC 정규화 + trim
 *  - 길이: grapheme cluster 기준 2~15자
 *  - 연속 공백 금지
 *  - 검증은 두 단계:
 *      (1) 원본 lowercase로 banned_words contains 검사 (욕설)
 *      (2) normalizedNickname(공백/특수문자 제거 + lowercase)으로
 *          reserved 정확 일치 + impersonation contains 검사
 *  - banned/reserved/impersonation 리스트는 resources/banned/*.txt에서 부팅 1회 로드
 *  - 외부 URL을 부팅 시 호출하지 않음(안정성/예측성 우선)
 */
@Component
public class NicknameValidator {

    public static final int MIN_LENGTH = 2;
    public static final int MAX_LENGTH = 15;

    private static final Pattern WHITESPACE = Pattern.compile("\\s{2,}");
    private static final Pattern NON_ALNUM_HANGUL = Pattern.compile("[^\\p{L}\\p{N}]");

    private Set<String> bannedWords = Set.of();
    private Set<String> reservedWords = Set.of();
    private Set<String> impersonationWords = Set.of();

    @PostConstruct
    void load() {
        bannedWords = loadLines("banned/banned_words.txt");
        reservedWords = loadLines("banned/reserved_words.txt");
        impersonationWords = loadLines("banned/impersonation_words.txt");
    }

    private Set<String> loadLines(String path) {
        Set<String> out = new HashSet<>();
        ClassPathResource res = new ClassPathResource(path);
        if (!res.exists()) return out;
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(res.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                String t = line.trim();
                if (t.isEmpty() || t.startsWith("#")) continue;
                out.add(t.toLowerCase(Locale.ROOT));
            }
        } catch (IOException e) {
            throw new IllegalStateException("금칙어 리스트 로드 실패: " + path, e);
        }
        return out;
    }

    /**
     * 닉네임 정규화: NFKC + trim. 사용자 표시는 이 결과를 그대로 저장.
     * null/blank → null.
     */
    public String normalize(String raw) {
        if (raw == null) return null;
        String n = Normalizer.normalize(raw, Normalizer.Form.NFKC).trim();
        return n.isEmpty() ? null : n;
    }

    /**
     * 검증 — 위반 시 400/403. 정규화된 닉네임 기준.
     */
    public void validate(String normalized) {
        if (normalized == null || normalized.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "닉네임을 입력해주세요");
        }
        int len = graphemeLength(normalized);
        if (len < MIN_LENGTH || len > MAX_LENGTH) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "닉네임은 " + MIN_LENGTH + "~" + MAX_LENGTH + "자여야 합니다");
        }
        if (WHITESPACE.matcher(normalized).find()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "닉네임에 연속 공백을 사용할 수 없습니다");
        }

        String lower = normalized.toLowerCase(Locale.ROOT);
        for (String bad : bannedWords) {
            if (lower.contains(bad)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "사용할 수 없는 닉네임입니다");
            }
        }

        String stripped = NON_ALNUM_HANGUL.matcher(lower).replaceAll("");
        if (reservedWords.contains(stripped)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "사용할 수 없는 닉네임입니다");
        }
        for (String imp : impersonationWords) {
            if (stripped.contains(imp)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "사용할 수 없는 닉네임입니다");
            }
        }
    }

    /**
     * 사용자가 보는 글자 수(grapheme cluster) 기준 길이.
     * 이모지/ZWJ 결합/한글 자모 결합 모두 1글자로 카운트.
     */
    int graphemeLength(String s) {
        BreakIterator it = BreakIterator.getCharacterInstance(Locale.ROOT);
        it.setText(s);
        int count = 0;
        for (int next = it.first(); (next = it.next()) != BreakIterator.DONE; ) {
            count++;
        }
        return count;
    }

    // 테스트 편의 (필요 시 외부 노출용)
    Set<String> bannedWords() { return bannedWords; }
    Set<String> reservedWords() { return reservedWords; }
    Set<String> impersonationWords() { return impersonationWords; }
}
