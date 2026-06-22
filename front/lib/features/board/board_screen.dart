import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/widgets/app_info_toast.dart';
import 'models/board_post.dart';
import 'data/board_mock.dart';
import 'board_detail_screen.dart';

/// 게시판 — 공지·소식 + 커뮤니티 **통합 단일 피드** (Q&A 제거).
/// 상단 카테고리 칩(공지/이벤트/패치/자유/거래후기/사기주의)으로 필터, 글 앞 타입칩.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

/// 게시판 노출 타입 (Q&A 제외). 공지성 + 커뮤니티 통합.
const List<BoardType> _boardTypes = [
  BoardType.notice,
  BoardType.event,
  BoardType.patch,
  BoardType.free,
  BoardType.tradeReview,
  BoardType.scamAlert,
];

class _BoardScreenState extends State<BoardScreen> {
  BoardType? _filter; // null = 전체

  @override
  Widget build(BuildContext context) {
    final posts = BoardMock.posts
        .where((p) =>
            _boardTypes.contains(p.type) && (_filter == null || p.type == _filter))
        .toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    // 글쓰기 FAB(우하단 확장형) 위로 마지막 글이 가리지 않게 — board 는 root Scaffold 라
    // body 가 SafeArea 밖 → 홈 인디케이터(viewPadding.bottom)까지 합산한 동적 하단 여백.
    final fabBottomInset = AppDimens.bottomContentInsetForExtendedFab +
        MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Text('게시판',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.blue,
        onPressed: () => AppInfoToast.show(context, '작성 화면은 다음 단계에서 추가돼요'),
        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
        label: const Text('글쓰기',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _categoryChips(),
          const SizedBox(height: 4),
          Expanded(
            child: posts.isEmpty
                ? const Center(
                    child: Text('아직 글이 없어요',
                        style: TextStyle(color: AppColors.textMuted)))
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, fabBottomInset),
                    itemCount: posts.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.dividerSoft),
                    itemBuilder: (_, i) => PostRow(post: posts[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip('전체', _filter == null, () => setState(() => _filter = null), AppColors.blue),
          for (final t in _boardTypes)
            _chip(t.label, _filter == t, () => setState(() => _filter = t), t.color),
        ],
      ),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? accent.withValues(alpha: 0.18) : AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: sel ? accent.withValues(alpha: 0.6) : AppColors.divider, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                color: sel ? accent : AppColors.textSecondary,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12.5,
              )),
        ),
      ),
    );
  }
}

class PostRow extends StatelessWidget {
  final BoardPost post;
  const PostRow({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BoardDetailScreen(post: post))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _typeChip(post.type),
                if (post.isPinned) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.push_pin, size: 13, color: AppColors.gold),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(post.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(post.body.replaceAll('\n', ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.35)),
            const SizedBox(height: 9),
            // 적응형 메타 — 넓으면 한 줄(양끝정렬), 좁거나 큰 글자면 메타가 둘째 줄로 전환.
            // 핵심정보(작성자·시간·조회·댓글·좋아요)를 ellipsis 로 숨기지 않음(Wrap 이 줄바꿈으로 처리).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  // 닉네임만 통제불가 단일필드라 최후수단 ellipsis(point6). 시간은 안 숨김.
                  Flexible(
                    child: Text(post.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  const _Dot(),
                  Text(BoardMock.relativeTime(post.createdAt),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                ]),
                // 메타는 폭이 모자라면 자기들끼리도 줄바꿈(숫자 안 숨김).
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _meta(Icons.visibility_outlined, post.viewCount),
                    _meta(Icons.chat_bubble_outline, post.commentCount),
                    if (post.likeCount > 0) _meta(Icons.favorite_border, post.likeCount),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(BoardType type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(type.icon, size: 12, color: type.color),
        const SizedBox(width: 4),
        Text(type.label,
            style: TextStyle(color: type.color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _meta(IconData icon, int n) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppColors.textMuted),
      const SizedBox(width: 3),
      Text('$n', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
    ]);
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('·', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
      );
}
