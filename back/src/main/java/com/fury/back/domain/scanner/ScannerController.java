package com.fury.back.domain.scanner;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.CardService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.*;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.multipart.MultipartFile;

import java.util.*;

@RestController
@RequestMapping("/api/scanner")
@RequiredArgsConstructor
public class ScannerController {

    private final CardService cardService;

    @Value("${scanner.base-url:http://localhost:8082}")
    private String scannerBaseUrl;

    @PostMapping("/identify")
    public ReturnData<?> identify(@RequestParam("image") MultipartFile image) {
        try {
            Map<String, Object> scanResult = callScannerApi(image);
            if (scanResult == null) {
                return ReturnData.notFound("스캐너 서버 연결 실패");
            }

            String status = (String) scanResult.get("status");
            if ("no_card".equals(status)) {
                return ReturnData.success(Map.of("status", "no_card"));
            }
            if ("not_found".equals(status) || scanResult.get("data") == null) {
                return ReturnData.success(Map.of("status", "not_found"));
            }

            @SuppressWarnings("unchecked")
            Map<String, Object> data = (Map<String, Object>) scanResult.get("data");
            @SuppressWarnings("unchecked")
            Map<String, Object> topResult = (Map<String, Object>) data.get("topResult");
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> candidates = (List<Map<String, Object>>) data.get("candidates");

            String cardId = (String) topResult.get("cardId");
            // 결과 시트에 가격/변동률을 표시하기 위해 enriched dto 사용. candidates는 thumbnail용이라 가격 불필요.
            var cardRes = cardService.getCardWithPrice(cardId);
            if (cardRes.getData() == null) {
                return ReturnData.notFound("카드 정보를 찾을 수 없습니다. cardId=" + cardId);
            }

            // 후보 카드들에 jpScrydexRef / enScrydexRef 보강
            List<Map<String, Object>> enrichedCandidates = List.of();
            if (candidates != null && !candidates.isEmpty()) {
                enrichedCandidates = candidates.stream().map(c -> {
                    String cid = (String) c.get("cardId");
                    var cRes = cardService.getCard(cid);
                    if (cRes.getData() != null) {
                        var enriched = new java.util.HashMap<>(c);
                        enriched.put("jpScrydexRef", cRes.getData().getJpScrydexRef());
                        enriched.put("enScrydexRef", cRes.getData().getEnScrydexRef());
                        return (Map<String, Object>) enriched;
                    }
                    return c;
                }).toList();
            }

            return ReturnData.success(Map.of(
                "status",     status,
                "card",       cardRes.getData(),
                "score",      topResult.get("score"),
                "candidates", enrichedCandidates
            ));

        } catch (Exception e) {
            return ReturnData.badRequest("스캔 처리 실패: " + e.getMessage());
        }
    }

    @PostMapping("/detect")
    public ResponseEntity<?> detect(@RequestParam("image") MultipartFile image) {
        try {
            SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
            factory.setConnectTimeout(3_000);
            factory.setReadTimeout(5_000);
            RestTemplate restTemplate = new RestTemplate(factory);

            ByteArrayResource resource = new ByteArrayResource(image.getBytes()) {
                @Override public String getFilename() { return image.getOriginalFilename(); }
            };

            MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
            body.add("image", resource);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);

            var response = restTemplate.postForEntity(
                scannerBaseUrl + "/detect",
                new HttpEntity<>(body, headers),
                Map.class
            );
            return ResponseEntity.ok(response.getBody());
        } catch (Exception e) {
            return ResponseEntity.ok(Map.of("found", false));
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> callScannerApi(MultipartFile image) {
        try {
            SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
            factory.setConnectTimeout(5_000);
            factory.setReadTimeout(30_000);
            RestTemplate restTemplate = new RestTemplate(factory);

            ByteArrayResource resource = new ByteArrayResource(image.getBytes()) {
                @Override public String getFilename() { return image.getOriginalFilename(); }
            };

            MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
            body.add("image", resource);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);

            var response = restTemplate.postForEntity(
                scannerBaseUrl + "/identify",
                new HttpEntity<>(body, headers),
                Map.class
            );

            return response.getBody();
        } catch (Exception e) {
            return null;
        }
    }
}
