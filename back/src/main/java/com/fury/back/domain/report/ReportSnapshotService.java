package com.fury.back.domain.report;

import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.board.BoardTaxonomy;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 신고 생성 시 게시판 원문 immutable snapshot 생성. ★현재 DB 콘텐츠를 서버가 직접 읽어 만든다(클라 입력 미신뢰).
 * raw authorId 미포함(authorLabel 만). 타임스탬프 ISO 문자열. 대상 미존재 → null(생성측이 거부 책임).
 */
@Service
@RequiredArgsConstructor
public class ReportSnapshotService {

    private final BoardPostRepository boardPostRepository;
    private final BoardCommentRepository boardCommentRepository;
    private final com.fury.back.domain.user.UserRepository userRepository;

    @Transactional(readOnly = true)
    public ReportedSnapshot build(String targetType, String targetId) {
        ReportedSnapshot snap = switch (targetType) {
            case "BOARD_POST" -> postSnapshot(targetId);
            case "BOARD_COMMENT" -> commentSnapshot(targetId);
            default -> null; // 비-board 는 snapshot 없음
        };
        // ★불완전 snapshot 저장 금지(증거 무결성). 콘텐츠 NOT NULL 이라 정상엔 안 나오나 서버 버그/이상 데이터 방어 — loud fail.
        if (snap != null && !snap.hasRequiredFields()) {
            throw new IllegalStateException("불완전한 신고 snapshot 필수 필드 누락: " + targetType + "/" + targetId);
        }
        return snap;
    }

    private ReportedSnapshot postSnapshot(String postId) {
        BoardPost p = boardPostRepository.findById(postId).filter(x -> x.getDeletedAt() == null).orElse(null);
        if (p == null) return null; // 미존재 또는 삭제 → snapshot 불가(생성측이 신고 거부)
        Set<String> ids = new HashSet<>();
        ids.add(p.getAuthorId()); // null 허용
        Map<String, String> nicks = nick(ids);
        return new ReportedSnapshot(
                ReportedSnapshot.CURRENT_VERSION, "BOARD_POST",
                p.getTitle(), p.getContent(),
                authorLabel(p.getType(), p.getAuthorId(), nicks),
                iso(p.getCreatedAt()), iso(p.getUpdatedAt()),
                null, null, null, null);
    }

    private ReportedSnapshot commentSnapshot(String commentId) {
        BoardComment c = boardCommentRepository.findById(commentId).filter(x -> x.getDeletedAt() == null).orElse(null);
        if (c == null) return null; // 미존재 또는 삭제
        BoardPost p = boardPostRepository.findById(c.getPostId()).orElse(null);
        String topId = c.getParentCommentId() != null ? c.getParentCommentId() : c.getCommentId();
        // 1쿼리 후 해당 최상위 thread(최상위 + 그 대댓글)만 — unrelated 제외.
        List<BoardComment> thread = boardCommentRepository.findByPostIdOrderByCreatedAtAsc(c.getPostId()).stream()
                .filter(x -> x.getCommentId().equals(topId) || topId.equals(x.getParentCommentId()))
                .toList();
        Set<String> ids = new HashSet<>();
        thread.forEach(x -> ids.add(x.getAuthorId()));
        Map<String, String> nicks = nick(ids);
        List<ReportedSnapshot.SnapshotComment> sc = thread.stream()
                .map(x -> new ReportedSnapshot.SnapshotComment(
                        x.getCommentId(), x.getParentCommentId(),
                        userLabel(x.getAuthorId(), nicks), x.getContent(), iso(x.getCreatedAt())))
                .toList();
        return new ReportedSnapshot(
                ReportedSnapshot.CURRENT_VERSION, "BOARD_COMMENT",
                null, null, null, null, null,
                p == null ? null : p.getTitle(), c.getCommentId(), topId, sc);
    }

    private Map<String, String> nick(Set<String> ids) {
        Set<String> clean = ids.stream().filter(s -> s != null && !s.isBlank()).collect(Collectors.toSet());
        if (clean.isEmpty()) return Map.of();
        Map<String, String> m = new HashMap<>();
        userRepository.findAllById(clean).forEach(u -> m.put(u.getUserId(), u.getNickname()));
        return m;
    }

    private String authorLabel(String type, String authorId, Map<String, String> nicks) {
        if (BoardTaxonomy.isAdminType(type)) return "운영팀";
        return userLabel(authorId, nicks);
    }

    private String userLabel(String authorId, Map<String, String> nicks) {
        if (authorId == null || authorId.isBlank()) return "(알 수 없음)";
        return nicks.getOrDefault(authorId, "(알 수 없음)");
    }

    private static String iso(LocalDateTime t) {
        return t == null ? null : t.toString();
    }
}
