package com.fury.back.domain.grading;

import com.fury.back.common.IdGenerator;
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
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class GradingServiceImpl implements GradingService {

    private final GradingResultRepository repository;
    private final RestTemplate restTemplate;

    @Value("${grading.service.url}")
    private String gradingServiceUrl;

    @Override
    public ReturnData<GradingResultDto> analyze(Map<String, MultipartFile> photos, String userId, String cardId) {
        GradingAnalysisDto analysis = callPythonService(photos);

        GradingResult entity = GradingResult.builder()
                .resultId(IdGenerator.generate())
                .userId(userId)
                .cardId(cardId)
                .centeringScore(analysis.getCenteringScore())
                .cornerScore(analysis.getCornerScore())
                .surfaceScore(analysis.getSurfaceScore())
                .whiteningScore(analysis.getWhiteningScore())
                .totalScore(analysis.getTotalScore())
                .heavyWhitening(analysis.isHeavyWhitening())
                .createdAt(LocalDateTime.now())
                .build();

        repository.save(entity);
        return ReturnData.success(toDto(entity));
    }

    @Override
    public ReturnData<List<GradingResultDto>> getHistory(String userId) {
        List<GradingResultDto> list = repository.findByUserIdOrderByCreatedAtDesc(userId)
                .stream().map(this::toDto).collect(Collectors.toList());
        return ReturnData.success(list);
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

    private GradingResultDto toDto(GradingResult e) {
        return GradingResultDto.builder()
                .resultId(e.getResultId())
                .cardId(e.getCardId())
                .centeringScore(e.getCenteringScore())
                .cornerScore(e.getCornerScore())
                .surfaceScore(e.getSurfaceScore())
                .whiteningScore(e.getWhiteningScore())
                .totalScore(e.getTotalScore())
                .heavyWhitening(e.isHeavyWhitening())
                .createdAt(e.getCreatedAt())
                .build();
    }
}
