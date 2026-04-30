package com.fury.back.domain.scanner;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.CardService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.multipart.MultipartFile;

import java.util.*;
import java.util.regex.*;

@RestController
@RequestMapping("/api/scanner")
@RequiredArgsConstructor
public class ScannerController {

    private final CardService cardService;

    @Value("${ollama.base-url:http://localhost:11434}")
    private String ollamaBaseUrl;

    @Value("${ollama.model:llava}")
    private String ollamaModel;

    @PostMapping("/identify")
    public ReturnData<?> identify(@RequestParam("image") MultipartFile image) {
        try {
            String base64 = Base64.getEncoder().encodeToString(image.getBytes());
            String number = callOllamaVision(base64);
            if (number == null) {
                return ReturnData.notFound("카드 번호를 인식하지 못했습니다");
            }
            return cardService.getCardsByCollectionNumber(number, "KO");
        } catch (Exception e) {
            return ReturnData.badRequest("스캔 처리 실패: " + e.getMessage());
        }
    }

    @SuppressWarnings("unchecked")
    private String callOllamaVision(String base64Image) {
        try {
            SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
            factory.setConnectTimeout(5_000);
            factory.setReadTimeout(60_000); // llava 응답 최대 60초
            RestTemplate restTemplate = new RestTemplate(factory);

            Map<String, Object> message = new HashMap<>();
            message.put("role", "user");
            message.put("content",
                "포켓몬 카드 하단의 수록번호를 읽어줘. " +
                "'023/198' 또는 '227/264' 같은 숫자/숫자 형태야. " +
                "그 형태로만 대답해. 못 찾으면 '없음'.");
            message.put("images", List.of(base64Image));

            Map<String, Object> body = new HashMap<>();
            body.put("model", ollamaModel);
            body.put("messages", List.of(message));
            body.put("stream", false);

            var response = restTemplate.postForEntity(
                ollamaBaseUrl + "/api/chat", body, Map.class);

            if (response.getBody() == null) return null;

            var msgMap = (Map<String, Object>) response.getBody().get("message");
            String content = String.valueOf(msgMap.get("content")).trim();

            Matcher m = Pattern.compile("(\\d{1,4})/(\\d{1,4})").matcher(content);
            if (m.find()) {
                int num = Integer.parseInt(m.group(1));
                return String.format("%03d", num) + "/" + m.group(2);
            }
            return null;
        } catch (Exception e) {
            return null;
        }
    }
}
