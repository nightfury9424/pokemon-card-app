package com.fury.back.domain.user;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface UserRepository extends JpaRepository<User, String> {
    Optional<User> findByGoogleId(String googleId);

    /**
     * 2026-05-29 admin Stage 0 (Codex H) — 사용자 검색.
     *   nickname partial match (LIKE %q%), email prefix match (LIKE q%) — PII safety.
     *   soft-deleted 사용자도 결과에 포함, frontend 에서 마스킹된 닉네임 그대로 표시.
     */
    @Query("""
            SELECT u FROM User u
            WHERE LOWER(u.nickname) LIKE LOWER(CONCAT('%', :q, '%'))
               OR LOWER(u.email) LIKE LOWER(CONCAT(:q, '%'))
            ORDER BY u.createdAt DESC
            """)
    List<User> searchByNicknameOrEmail(@Param("q") String q, Pageable pageable);

    @Query("SELECT COUNT(u) > 0 FROM User u WHERE LOWER(u.nickname) = LOWER(:nickname)")
    boolean existsByNicknameIgnoreCase(@Param("nickname") String nickname);

    /**
     * 활성 사용자(deleted_at IS NULL) 한정 닉네임 중복 체크. 탈퇴자 마스킹 닉네임은 제외.
     * Check API + onboarding/change submit pre-check + DB partial unique index 와 정렬된 사양.
     */
    @Query("SELECT COUNT(u) > 0 FROM User u WHERE LOWER(u.nickname) = LOWER(:nickname) AND u.deletedAt IS NULL")
    boolean existsByNicknameIgnoreCaseAndDeletedAtIsNull(@Param("nickname") String nickname);
}
