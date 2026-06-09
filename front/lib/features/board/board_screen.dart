import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import 'models/board_post.dart';
import 'data/board_mock.dart';
import 'board_detail_screen.dart';

/// 게시판 — 공지·소식(관리자) / 커뮤니티 / Q&A 3섹션.
/// post-launch 신기능. 현재 목업 데이터, 백엔드는 승인 후 연결.
class BoardScreen extends StatefulWidget {
  final BoardSection initialSection;
  const BoardScreen({super.key, this.initialSection = BoardSection.official});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late BoardSection _section = widget.initialSection;
  BoardType? _filter; // null = 전체

  void _selectSection(BoardSection s) {
    if (s == _section) return;
    setState(() {
      _section = s;
      _filter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final posts = BoardMock.bySection(_section, filter: _filter);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Text('게시판',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      floatingActionButton: _section.userWritable
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.blue,
              onPressed: () => AppInfoToast.show(context, '작성 화면은 다음 단계에서 추가돼요'),
              icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
              label: const Text('글쓰기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
      body: Column(
        children: [
          _sectionTabs(),
          if (_section.types.length > 1) _categoryChips(),
          const SizedBox(height: 4),
          Expanded(
            child: posts.isEmpty
                ? const Center(
                    child: Text('아직 글이 없어요', style: TextStyle(color: AppColors.textMuted)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: posts.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.dividerSoft),
                    itemBuilder: (_, i) => _PostRow(post: posts[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: BoardSection.values.map((s) {
          final sel = s == _section;
          return Expanded(
            child: GestureDetector(
              onTap: () => _selectSection(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? AppColors.blueDeep : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Text(
                  s.label,
                  style: TextStyle(
                    color: sel ? Colors.white : AppColors.textSecondary,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _categoryChips() {
    final types = _section.types;
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip('전체', _filter == null, () => setState(() => _filter = null), AppColors.blue),
          for (final t in types)
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

class _PostRow extends StatelessWidget {
  final BoardPost post;
  const _PostRow({required this.post});

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
                if (post.type == BoardType.qna && post.isAnswered) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('답변완료',
                        style: TextStyle(color: AppColors.green, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ),
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
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35)),
            const SizedBox(height: 9),
            Row(
              children: [
                Text(post.author,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                const _Dot(),
                Text(BoardMock.relativeTime(post.createdAt),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                const Spacer(),
                _meta(Icons.visibility_outlined, post.viewCount),
                const SizedBox(width: 12),
                _meta(Icons.chat_bubble_outline, post.commentCount),
                if (post.likeCount > 0) ...[
                  const SizedBox(width: 12),
                  _meta(Icons.favorite_border, post.likeCount),
                ],
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
