package com.fury.back.domain.admin;

import com.fury.back.common.IdGenerator;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 2026-05-29 admin Stage 0 audit log helper.
 *
 * <p>모든 admin 액션 기록 — 신고 처리, 사용자 정지/복구, 거래글 삭제.
 * INSERT only. App Review 5.1.5 moderation evidence 의무.</p>
 */
@Service
@RequiredArgsConstructor
public class AdminActionService {

    private final AdminActionRepository adminActionRepository;

    @Transactional
    public AdminAction record(String adminUserId, String actionType,
                              String targetType, String targetId,
                              String reportId, String memo,
                              String previousState, String newState) {
        AdminAction action = AdminAction.builder()
                .actionId(IdGenerator.generate())
                .adminUserId(adminUserId)
                .actionType(actionType)
                .targetType(targetType)
                .targetId(targetId)
                .reportId(reportId)
                .memo(memo)
                .previousState(previousState)
                .newState(newState)
                .build();
        return adminActionRepository.save(action);
    }
}
