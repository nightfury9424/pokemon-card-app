import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'models/board_post.dart';
import 'data/board_repository.dart';
import 'board_screen.dart';
import 'board_detail_screen.dart';
import 'models/board_filter.dart';

/// 홈 카드 위 얇은 가로 공지배너 — 서버의 첫 유효 공지(핀 우선·최신순) 1개. 탭 → 상세 / › → 공지 목록.
/// ★실 API 연결: GET /api/board/posts?section=official&type=notice. 로딩/0건/오류 = 배너 숨김(홈 비차단, 가짜 static 금지).
/// pull-to-refresh 재조회는 홈이 GlobalKey 로 refresh() 호출(관리자 공지 변경 → 최신 반영).
class HomeNoticeBanner extends StatefulWidget {
  final BoardRepository repository;
  const HomeNoticeBanner({
    super.key,
    this.repository = const BoardRepository(),
  });

  @override
  HomeNoticeBannerState createState() => HomeNoticeBannerState();
}

class HomeNoticeBannerState extends State<HomeNoticeBanner> {
  BoardPost? _post; // 첫 유효 공지. null = 로딩/0건/오류 → 배너 숨김.
  int _reqId = 0; // 늦게 온(stale) 응답이 최신 상태를 덮지 않도록.

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// 홈 pull-to-refresh 에서 await 가능하도록 Future 반환(관리자 공지 변경 → 최신 반영).
  /// _fetch 내부에서 오류를 자체 흡수(throw 안 함) → 홈 새로고침을 차단하지 않음. 탭 재진입은 IndexedStack 유지라 재호출 없음.
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    final reqId = ++_reqId;
    try {
      // 서버 반환 순서 그대로(핀 우선 → 최신순). 첫 유효 공지만 사용. hidden/deleted 는 서버가 이미 제외.
      final res = await widget.repository.fetchList(
        section: 'official',
        type: 'notice',
        page: 0,
        size: 5,
      );
      if (!mounted || reqId != _reqId) return; // stale 폐기
      setState(() => _post = res.posts.isEmpty ? null : res.posts.first);
    } catch (_) {
      if (!mounted || reqId != _reqId) return;
      setState(() => _post = null); // 오류 → 배너 숨김(홈 전체 오류로 전환 금지·가짜 공지 금지)
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    if (p == null) return const SizedBox.shrink(); // 로딩/0건/오류 = 숨김

    // 포인터 탭(GestureDetector)과 스크린리더 탭(Semantics.onTap)이 같은 동작을 쓰도록 콜백 공유.
    void openDetail() => Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => BoardDetailScreen(postId: p.id, summary: p),
      ),
    );
    void openList() => Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(
        builder: (_) => const BoardScreen(initialFilter: BoardFilter.notice)));

    // ★접근성: 배너 전체를 상세 탭으로 감싸지 않고, 상세 영역 / 목록 영역을 형제 버튼 2개로 분리(중첩 시 스크린리더
    //   focus/action 병합 위험). 각 Semantics 가 onTap(=tap action) 직접 보유 — excludeSemantics 로 자식 GestureDetector
    //   액션이 사라지지 않게. 두 영역 모두 SizedBox(height 46)로 풀 높이 터치 보장(Expanded 는 너비만 채움).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Row(
          children: [
            // ── 상세 버튼(형제 1): 아이콘·유형배지·제목 포함, 라벨에 실제 제목 포함. 터치 높이 46 보장 ──
            Expanded(
              child: SizedBox(
                height: 46,
                child: Semantics(
                  button: true,
                  label: '공지 상세 보기: ${p.title}',
                  onTap: openDetail,
                  excludeSemantics: true, // 내부 제목/배지/아이콘 중복 낭독 방지(라벨에 제목 포함)
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: openDetail,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.campaign,
                          size: 17,
                          color: AppColors.blueLight,
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: p.type.color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            p.type.label,
                            style: TextStyle(
                              color: p.type.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── 목록 버튼(형제 2): › → 공지 목록(공지 탭). 터치 44×46, 아이콘 우측정렬로 시각 위치 유지 ──
            Semantics(
              button: true,
              label: '공지 목록 보기',
              onTap: openList,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: openList,
                child: const SizedBox(
                  width: 44,
                  height: 46,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
