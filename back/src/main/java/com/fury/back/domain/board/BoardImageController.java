package com.fury.back.domain.board;

import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;

@Tag(name = "BoardImage", description = "게시판 이미지 임시 업로드")
@RestController
@RequestMapping("/api/board/images")
@RequiredArgsConstructor
public class BoardImageController {

    private final BoardImageService boardImageService;

    @Operation(summary = "게시판 이미지 업로드(임시)",
            description = "검증 후 S3 저장 → uploadId 반환. 작성/수정 시 imageUploadIds 로 연결(raw key 직접 연결 불가).")
    @PostMapping(consumes = "multipart/form-data")
    public ReturnData<Map<String, String>> upload(
            @AuthenticationPrincipal String userId,
            @RequestPart("file") MultipartFile file) {
        return ReturnData.success(Map.of("uploadId", boardImageService.upload(userId, file)));
    }
}
