package com.fury.back.domain.grading;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingAnalysisDto;
import com.fury.back.domain.grading.dto.GradingResultDto;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.*;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class GradingServiceImpl implements GradingService {

    private final RestTemplate restTemplate;

    @Value("${grading.service.url}")
    private String gradingServiceUrl;

    @Value("${scanner.base-url:http://localhost:8082}")
    private String scannerBaseUrl;

    @Override
    public ReturnData<GradingResultDto> analyze(
            Map<String, MultipartFile> photos, String cardId,
            Double frameX, Double frameY, Double frameW, Double frameH) {
        boolean identityVerified = verifyIdentity(photos.get("front_image"), cardId);
        GradingAnalysisDto analysis = callPythonService(photos, frameX, frameY, frameW, frameH);
        analysis.setIdentityVerified(identityVerified);
        return ReturnData.success(GradingResultDto.builder()
                .centeringScore(analysis.getCenteringScore())
                .cornerScore(analysis.getCornerScore())
                .surfaceScore(analysis.getSurfaceScore())
                .whiteningScore(analysis.getWhiteningScore())
                .totalScore(analysis.getTotalScore())
                .heavyWhitening(analysis.isHeavyWhitening())
                .centeringRatio(analysis.getCenteringRatio())
                .detectionConfidence(analysis.getDetectionConfidence())
                .centeringDetail(analysis.getCenteringDetail())
                .cornerDetail(analysis.getCornerDetail())
                .surfaceDetail(analysis.getSurfaceDetail())
                .whiteningDetail(analysis.getWhiteningDetail())
                .identityVerified(analysis.isIdentityVerified())
                .edgeScore(analysis.getEdgeScore())
                .edgeDetail(analysis.getEdgeDetail())
                .weightedScore(analysis.getWeightedScore())
                .totalScoreDisplay(analysis.getTotalScoreDisplay())
                .grade(analysis.getGrade())
                .gradeColor(analysis.getGradeColor())
                .deductionReasons(analysis.getDeductionReasons())
                .defectRegions(analysis.getDefectRegions())
                .hasMajorDefect(analysis.isHasMajorDefect())
                .retakeRequired(analysis.isRetakeRequired())
                .retakeReason(analysis.getRetakeReason())
                .captureQuality(analysis.getCaptureQuality())
                .screenSuspected(analysis.isScreenSuspected())
                .screenSuspectReason(analysis.getScreenSuspectReason())
                .build());
    }

    private boolean verifyIdentity(MultipartFile frontImage, String assetCardId) {
        if (frontImage == null || frontImage.isEmpty() || assetCardId == null || assetCardId.isBlank()) {
            return false;
        }

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);

            ByteArrayResource resource = new ByteArrayResource(frontImage.getBytes()) {
                @Override public String getFilename() { return frontImage.getOriginalFilename(); }
            };

            MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
            body.add("image", resource);  // /identify uses "image" field

            SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
            factory.setConnectTimeout(5_000);
            factory.setReadTimeout(30_000);
            RestTemplate rt = new RestTemplate(factory);
            ResponseEntity<Map> response = rt.postForEntity(
                    scannerBaseUrl + "/identify",
                    new HttpEntity<>(body, headers),
                    Map.class
            );

            Map<?, ?> result = response.getBody();
            if (result == null) return false;

            // /identify returns: { status, data: { topResult: { cardId, score }, candidates, ocrNumber } }
            String status = result.get("status") instanceof String s ? s : "";
            if (!"success".equals(status) && !"low_confidence".equals(status)) return false;

            Object dataRaw = result.get("data");
            if (!(dataRaw instanceof Map<?, ?> data)) return false;
            Object topRaw = data.get("topResult");
            if (!(topRaw instanceof Map<?, ?> top)) return false;

            String scannedCardId = top.get("cardId") instanceof String s ? s : null;
            double confidence = top.get("score") instanceof Number n ? n.doubleValue() : 0.0;

            return confidence > 0.7 && assetCardId.equals(scannedCardId);
        } catch (Exception e) {
            return false;
        }
    }

    private GradingAnalysisDto callPythonService(
            Map<String, MultipartFile> photos,
            Double frameX, Double frameY, Double frameW, Double frameH) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.MULTIPART_FORM_DATA);
        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        photos.forEach((name, file) -> {
            try {
                ByteArrayResource resource = new ByteArrayResource(file.getBytes()) {
                    @Override public String getFilename() { return file.getOriginalFilename(); }
                };
                body.add(name, resource);
            } catch (IOException e) {
                throw new RuntimeException("사진 읽기 실패: " + name, e);
            }
        });
        if (frameX != null && frameY != null && frameW != null && frameH != null) {
            body.add("frame_x", frameX.toString());
            body.add("frame_y", frameY.toString());
            body.add("frame_w", frameW.toString());
            body.add("frame_h", frameH.toString());
        }
        HttpEntity<MultiValueMap<String, Object>> request = new HttpEntity<>(body, headers);
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(90_000);
        RestTemplate rt = new RestTemplate(factory);
        ResponseEntity<GradingAnalysisDto> response = rt.postForEntity(
                gradingServiceUrl + "/analyze", request, GradingAnalysisDto.class);
        return response.getBody();
    }
}
