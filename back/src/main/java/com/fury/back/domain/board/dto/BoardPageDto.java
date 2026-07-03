package com.fury.back.domain.board.dto;

import java.util.List;

/** 게시글 목록 페이지 응답. */
public record BoardPageDto(
        List<BoardPostSummaryDto> content,
        int page,
        int size,
        long totalElements,
        int totalPages
) {}
