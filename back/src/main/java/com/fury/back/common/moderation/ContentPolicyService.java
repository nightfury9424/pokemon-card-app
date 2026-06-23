package com.fury.back.common.moderation;

import jakarta.annotation.PostConstruct;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * 공용 사용자 작성 콘텐츠 금칙어 검사(게시판·댓글; 이후 승인 시 채팅·거래글).
 *
 * <p>정책(보수적 1차): 외부 목록 미확대, 기존 {@code banned/banned_words.txt} 기준. 검사 시에만
 * 비교본 생성(원문 미변경·미저장). 오탐 방지 우선 — 초성/유사문자 등 공격적 변형은 1차 제외.
 * 탐지 단어·원문은 로그/응답에 남기지 않는다.
 *
 * <p>정규화 단계: NFKC → lowercase → 제로폭 제거 → (정상어 allowlist 소거) → 끼운 구분자(공백·점·일부
 * 특수문자) 제거 비교본 → 과도 반복문자 축약 비교본. base/compact/collapsed 중 하나라도 포함 시 위반.
 */
@Component
public class ContentPolicyService {

    /** 사용자 표시 문구(고정). 탐지 단어 미노출. */
    public static final String VIOLATION_MESSAGE = "부적절한 표현이 포함되어 있어 등록할 수 없습니다.";

    private static final Pattern ZERO_WIDTH = Pattern.compile("[\\u200B-\\u200D\\uFEFF\\u2060\\u00AD]");
    // 우회용으로 글자 사이에 끼우는 보수적 구분자 집합(문자/숫자/한글은 제거 안 함 — 오탐 방지).
    private static final Pattern SEPARATORS = Pattern.compile("[\\s.,·∙•・’'\"\\-_*~^|/\\\\()\\[\\]{}]+");
    private static final Pattern REPEATS = Pattern.compile("(.)\\1{2,}");

    private Set<String> banned = Set.of();
    private Set<String> allow = Set.of();

    @PostConstruct
    void load() {
        banned = loadLines("banned/banned_words.txt");
        allow = loadLines("moderation/content_allowlist.txt"); // 없으면 빈 셋(오탐 예외, 추후 운영 큐레이션)
    }

    /** 위반 시 ContentPolicyViolationException(advice 가 403 + CONTENT_POLICY_VIOLATION). */
    public void check(String text) {
        if (violates(text)) {
            throw new ContentPolicyViolationException(VIOLATION_MESSAGE);
        }
    }

    /** 여러 필드(제목·본문 등) 일괄 검사. */
    public void checkAll(String... texts) {
        if (texts == null) return;
        for (String t : texts) check(t);
    }

    public boolean violates(String text) {
        return matches(text, banned, allow);
    }

    // ── 순수 함수(네트워크/스프링 무관, 단위테스트 가능) ──

    /** text 가 banned 중 하나라도 포함하면 true. allow(정상어)는 검사 전 소거(오탐 방지). */
    static boolean matches(String text, Set<String> banned, Set<String> allow) {
        if (text == null || text.isEmpty() || banned == null || banned.isEmpty()) return false;
        String base = normalizeBase(text);
        if (allow != null) {
            for (String a : allow) {
                if (!a.isEmpty()) base = base.replace(a, " "); // 정상어 먼저 소거
            }
        }
        String compact = SEPARATORS.matcher(base).replaceAll(""); // 끼운 구분자 제거 비교본
        String collapsed = REPEATS.matcher(compact).replaceAll("$1"); // 과도 반복 축약 비교본
        for (String bad : banned) {
            if (bad.isEmpty()) continue;
            if (base.contains(bad) || compact.contains(bad) || collapsed.contains(bad)) {
                return true;
            }
        }
        return false;
    }

    /** NFKC + lowercase + 제로폭 제거. (공백·특수문자는 base 에선 유지 — 경계 보존으로 오탐 최소화.) */
    static String normalizeBase(String text) {
        String n = Normalizer.normalize(text, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT);
        return ZERO_WIDTH.matcher(n).replaceAll("");
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
            // 로드 실패 시 빈 셋(차단 안 함, 부팅 막지 않음). 운영 모니터링 별도.
        }
        return out;
    }
}
