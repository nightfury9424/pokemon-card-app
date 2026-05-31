package com.fury.back.domain.grading;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingResultDto;
import org.springframework.web.multipart.MultipartFile;
import java.util.Map;

public interface GradingService {
    ReturnData<GradingResultDto> analyze(
            Map<String, MultipartFile> photos,
            String cardId,
            Double frameX, Double frameY, Double frameW, Double frameH);
}
