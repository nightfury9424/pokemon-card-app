package com.fury.back.domain.admin;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fury.back.common.ReturnData;
import com.fury.back.storage.ImageStorageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.io.InputStream;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 점검(maintenance) 토글 — admin이 app-config/maintenance.json(S3, card CDN d3shjhylvfe40j 서빙)을 켜고 끔.
 *
 * <p>앱은 이 정적 JSON을 60초 폴링 → {@code maintenance:true}면 전 버전 점검화면(MaintenanceGate).
 * 백엔드 다운과 독립이라 긴급 백서버 점검에 적합. CDN/object TTL(~30s) 만큼 반영 지연 가능(허용 범위).</p>
 *
 * <p>★버전 구분 없음 — 1.0.0/1.0.1 모두 차단. "구버전만 강제 업데이트"는 별도 버전 게이트(미구현).</p>
 */
@Slf4j
@RestController
@RequestMapping("/api/admin/maintenance")
@RequiredArgsConstructor
public class AdminMaintenanceController {

    private static final String KEY = "app-config/maintenance.json";
    private static final String DEFAULT_MSG = "더 나은 서비스를 위해 점검 중입니다.\n잠시 후 다시 이용해 주세요.";

    private final ImageStorageService imageStorage;
    private final AdminActionService adminActionService;
    private final ObjectMapper objectMapper;

    /** 현재 점검 상태 — S3에서 직접 읽음(CDN 캐시 우회 = 최신값 보장). */
    @GetMapping
    public ReturnData<?> current() {
        return ReturnData.success(read());
    }

    /** 점검 켜기/끄기 — JSON 덮어쓰기 + audit. message 비면 기본 문구 사용. */
    @PostMapping
    public ReturnData<?> set(@RequestBody Map<String, Object> body,
                             @AuthenticationPrincipal String adminUserId) {
        boolean on = Boolean.TRUE.equals(body.get("maintenance"));
        String msg = body.get("message") == null ? "" : body.get("message").toString().trim();
        if (on && msg.isBlank()) msg = DEFAULT_MSG;

        Map<String, Object> json = new LinkedHashMap<>();
        json.put("maintenance", on);
        json.put("message", msg);
        try {
            imageStorage.putRaw(KEY, objectMapper.writeValueAsBytes(json), "application/json");
        } catch (Exception e) {
            log.error("[Maintenance] maintenance.json 쓰기 실패", e);
            return ReturnData.fail("F_MAINT", "점검 상태 저장 실패: " + e.getMessage());
        }
        String actor = (adminUserId == null || adminUserId.isBlank()) ? "UNKNOWN" : adminUserId;
        adminActionService.record(actor, on ? "MAINTENANCE_ON" : "MAINTENANCE_OFF",
                "SYSTEM", "maintenance", null, on ? msg : "점검 해제", null, null);
        log.warn("[Maintenance] {} by {}", on ? "ON" : "OFF", actor);
        return ReturnData.success(json);
    }

    private Map<String, Object> read() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("maintenance", false);
        out.put("message", "");
        try (InputStream in = imageStorage.load(KEY)) {
            JsonNode n = objectMapper.readTree(in.readAllBytes());
            out.put("maintenance", n.path("maintenance").asBoolean(false));
            out.put("message", n.path("message").asText(""));
        } catch (Exception e) {
            // 파일 없음/파싱 실패 → 점검 아님(fail-safe).
        }
        return out;
    }
}
