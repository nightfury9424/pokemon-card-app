package com.fury.back.domain.grading;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingAnalysisDto;
import com.fury.back.domain.grading.dto.GradingResultDto;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.*;
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

    @Override
    public ReturnData<GradingResultDto> analyze(Map<String, MultipartFile> photos) {
        GradingAnalysisDto analysis = callPythonService(photos);
        return ReturnData.success(GradingResultDto.builder()
                .centeringScore(analysis.getCenteringScore())
                .cornerScore(analysis.getCornerScore())
                .surfaceScore(analysis.getSurfaceScore())
                .whiteningScore(analysis.getWhiteningScore())
                .totalScore(analysis.getTotalScore())
                .heavyWhitening(analysis.isHeavyWhitening())
                .centeringDetail(analysis.getCenteringDetail())
                .cornerDetail(analysis.getCornerDetail())
                .surfaceDetail(analysis.getSurfaceDetail())
                .whiteningDetail(analysis.getWhiteningDetail())
                .build());
    }

    private GradingAnalysisDto callPythonService(Map<String, MultipartFile> photos) {
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
        HttpEntity<MultiValueMap<String, Object>> request = new HttpEntity<>(body, headers);
        ResponseEntity<GradingAnalysisDto> response = restTemplate.postForEntity(
                gradingServiceUrl + "/analyze", request, GradingAnalysisDto.class);
        return response.getBody();
    }
}
