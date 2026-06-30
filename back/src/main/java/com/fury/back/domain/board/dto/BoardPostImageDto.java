package com.fury.back.domain.board.dto;

/**
 * 게시글 첨부 이미지 상세 항목.
 * imageId = 수정 시 기존 이미지 유지·순서 지정용. url = secure proxy URL. raw S3 storage key 는 미노출.
 */
public record BoardPostImageDto(String imageId, String url, int sortOrder) {}
