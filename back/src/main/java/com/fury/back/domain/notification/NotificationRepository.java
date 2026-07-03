package com.fury.back.domain.notification;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface NotificationRepository extends JpaRepository<Notification, String> {
    Page<Notification> findByUserIdOrderByCreatedAtDesc(String userId, Pageable pageable);
    List<Notification> findTop50ByUserIdOrderByCreatedAtDesc(String userId);
    long countByUserIdAndIsReadFalse(String userId);

    /**
     * dedup_key 멱등 INSERT. 이미 같은 dedup_key 알림이 있으면 no-op(0행) → 중복 알림/푸시 방지.
     * 반환 affected rows == 1 일 때만 신규 알림 → 호출부가 push.
     */
    @Modifying
    @Query(value = "INSERT INTO notifications "
            + "(notification_id, user_id, type, title, body, link_url, dedup_key, is_read, created_at) "
            + "VALUES (:id, :userId, :type, :title, :body, :linkUrl, :dedupKey, false, now()) "
            + "ON CONFLICT (dedup_key) DO NOTHING", nativeQuery = true)
    int insertIgnoreDedup(@Param("id") String id, @Param("userId") String userId,
            @Param("type") String type, @Param("title") String title, @Param("body") String body,
            @Param("linkUrl") String linkUrl, @Param("dedupKey") String dedupKey);
}
