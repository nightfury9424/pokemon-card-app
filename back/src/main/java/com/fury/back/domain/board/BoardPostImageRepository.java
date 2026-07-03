package com.fury.back.domain.board;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;

public interface BoardPostImageRepository extends JpaRepository<BoardPostImage, String> {

    List<BoardPostImage> findByPostIdOrderBySortOrderAsc(String postId);

    /** 목록 imageCount batch(N+1 차단). */
    List<BoardPostImage> findByPostIdInOrderBySortOrderAsc(Collection<String> postIds);

    void deleteByPostId(String postId);

    long countByPostId(String postId);
}
