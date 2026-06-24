package com.fury.back.domain.board.dto;

import java.util.List;

/**
 * 사용자 본인 글 수정(제목·본문 + 이미지 재구성). type 변경 불가(official 승격 차단).
 * images = 최종 이미지 순서. null = 이미지 미변경(기존 유지), 빈 리스트 = 전부 제거.
 */
public record UpdatePostRequest(String title, String content, List<ImageItem> images) {
    public UpdatePostRequest(String title, String content) {
        this(title, content, null);
    }

    /** 항목당 정확히 하나만: 기존 유지=existingImageId / 신규 추가=uploadId. */
    public record ImageItem(String existingImageId, String uploadId) {}
}
