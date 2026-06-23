import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import 'models/board_post.dart';
import 'data/board_repository.dart';
import 'board_compose_screen.dart';

/// 게시글 상세 — postId 로 상세 API 재조회(목록 summary 재사용 X).
/// 공지(official: notice/event/patch) = 본문만 읽기(댓글·반응 UI 없음).
/// 자유(free) = 본문 + 댓글·1단 대댓글 읽기(작성/좋아요 동작은 다음 슬라이스).
class BoardDetailScreen extends StatefulWidget {
  final String postId;
  final BoardRepository repository;

  /// 목록에서 넘어올 때 로딩 중 AppBar 제목 등 표시용(최종 데이터는 fetchDetail).
  final BoardPost? summary;

  const BoardDetailScreen({
    super.key,
    required this.postId,
    this.repository = const BoardRepository(),
    this.summary,
  });

  @override
  State<BoardDetailScreen> createState() => _BoardDetailScreenState();
}

class _BoardDetailScreenState extends State<BoardDetailScreen> {
  BoardPost? _post;
  bool _loading = true;
  bool _notFound = false;
  Object? _error;

  // 댓글/대댓글 입력
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  BoardComment? _replyTo; // 답글 대상(컨텍스트 칩). null = 일반 댓글
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _commentCtrl.addListener(_onCommentChange);
    _load();
  }

  void _onCommentChange() {
    if (mounted) setState(() {}); // 전송 버튼 활성/비활성 갱신
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
      _error = null;
    });
    try {
      final p = await widget.repository.fetchDetail(widget.postId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (p == null) {
          _notFound = true; // 404 = 삭제/숨김/미존재
        } else {
          _post = p;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  // 댓글 작성·삭제 후 무플래시 재조회(로딩 스피너 전환 없이 _post 갱신 → 목록·댓글 수 갱신).
  Future<void> _reload() async {
    try {
      final p = await widget.repository.fetchDetail(widget.postId);
      if (!mounted || p == null) return;
      setState(() => _post = p);
    } catch (_) {
      // 재조회 실패는 기존 화면 유지(조용히 무시).
    }
  }

  // 본인 자유글(canEdit/canDelete)일 때만 ⋯ 메뉴. 공식글·타인글은 서버 플래그 false → 미노출.
  List<Widget>? _appBarActions() {
    final p = _post;
    if (p == null || !(p.canEdit || p.canDelete)) return null;
    return [
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
        color: AppColors.surfaceCard,
        onSelected: (v) {
          if (v == 'edit') _edit(p);
          if (v == 'delete') _delete(p);
        },
        itemBuilder: (_) => [
          if (p.canEdit)
            const PopupMenuItem(
                value: 'edit',
                child: Text('수정', style: TextStyle(color: AppColors.textPrimary))),
          if (p.canDelete)
            const PopupMenuItem(
                value: 'delete', child: Text('삭제', style: TextStyle(color: AppColors.red))),
        ],
      ),
    ];
  }

  Future<void> _edit(BoardPost p) async {
    final updated = await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => BoardComposeScreen(repository: widget.repository, editing: p)));
    if (updated != null && mounted) _load(); // 수정 성공 → 상세 갱신
  }

  Future<void> _delete(BoardPost p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('글을 삭제할까요?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: const Text('삭제한 글은 복구할 수 없어요.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제',
                  style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.deletePost(p.id);
      if (!mounted) return;
      Navigator.of(context).pop('deleted'); // 목록으로 변경 신호 → 새로고침
    } on BoardApiException catch (e) {
      if (!mounted) return;
      AppInfoToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppInfoToast.show(context, '삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleType = (_post ?? widget.summary)?.type;
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(titleType?.label ?? '게시글',
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        actions: _appBarActions(),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_notFound) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('삭제되었거나 존재하지 않는 글이에요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        ),
      );
    }
    if (_error != null || _post == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('글을 불러오지 못했어요.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _load,
              child: const Text('다시 시도',
                  style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    final post = _post!;
    final isOfficial = post.isAdmin; // notice/event/patch = 관리자 공지계열

    // 공지 = 본문만(댓글·반응·입력 없음). 자유 = 본문 + 댓글 트리 + 입력바(동작은 다음 슬라이스).
    final content = ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _header(post),
        const SizedBox(height: 18),
        Text(post.body,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, height: 1.6)),
        if (!isOfficial) ...[
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),
          Text('댓글 ${post.commentCount}',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...post.comments.map(_commentTile),
          if (post.comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('아직 댓글이 없어요',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13))),
            ),
        ],
      ],
    );

    if (isOfficial) return content;
    return Column(children: [Expanded(child: content), _commentBar()]);
  }

  Widget _header(BoardPost post) {
    // 작성자 이니셜 — 빈 author(서버 라벨 누락)에도 .characters.first 가 throw 하지 않도록 가드.
    final initial = post.author.isEmpty ? '?' : post.author.characters.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: post.type.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(post.type.icon, size: 13, color: post.type.color),
              const SizedBox(width: 5),
              Text(post.type.label,
                  style: TextStyle(
                      color: post.type.color, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (post.isPinned) ...[
            const SizedBox(width: 7),
            const Icon(Icons.push_pin, size: 14, color: AppColors.gold),
          ],
        ]),
        const SizedBox(height: 12),
        Text(post.title,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3)),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.surfaceElevated,
                child: Text(initial,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(post.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (post.isAdmin) ...[const SizedBox(width: 6), _adminBadge()],
            ]),
            // 조회수는 0이면 숨김(증가 기능 전이라 '조회 0' 반복 노출 방지).
            Text(
              post.viewCount > 0
                  ? '${boardRelativeTime(post.createdAt)} · 조회 ${post.viewCount}'
                  : boardRelativeTime(post.createdAt),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ],
    );
  }

  // 1단 대댓글 읽기 표시. Q&A 채택 UI 는 1.0.4 미노출(데이터는 파싱 유지).
  Widget _commentTile(BoardComment c, {bool isReply = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 28 : 0, 10, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (isReply)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.subdirectory_arrow_right,
                          size: 13, color: AppColors.textMuted),
                    ),
                  Flexible(
                    child: Text(c.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (c.isAdmin) ...[const SizedBox(width: 5), _adminBadge()],
                  const SizedBox(width: 8),
                  Text(boardRelativeTime(c.createdAt),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                ]),
                const SizedBox(height: 6),
                Text(c.body,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                _commentActions(c),
              ],
            ),
          ),
          ...c.replies.map((r) => _commentTile(r, isReply: true)),
        ],
      ),
    );
  }

  Widget _adminBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text('운영',
          style: TextStyle(color: AppColors.blueLight, fontSize: 9.5, fontWeight: FontWeight.w800)),
    );
  }

  static const _commentMax = 2000; // 서버 COMMENT_MAX 와 동일

  // 댓글/대댓글 액션(답글·삭제). 플래그(canReply+target / canDelete)로 노출 제어.
  // 삭제 placeholder·삭제된 top 아래 답글은 서버 플래그가 canReply=false → 답글 버튼 자동 미노출.
  Widget _commentActions(BoardComment c) {
    final canReply = c.canReply && c.replyTargetCommentId != null;
    if (!canReply && !c.canDelete) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        if (canReply) _commentAction('답글', () => _startReply(c)),
        if (canReply && c.canDelete) const SizedBox(width: 14),
        if (c.canDelete) _commentAction('삭제', () => _deleteComment(c), color: AppColors.red),
      ]),
    );
  }

  Widget _commentAction(String label, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(label,
            style: TextStyle(
                color: color ?? AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _startReply(BoardComment c) {
    setState(() => _replyTo = c);
    _commentFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyTo = null);

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return; // 빈/공백·연타 가드
    setState(() => _sending = true);
    final parentId = _replyTo?.replyTargetCommentId; // 답글이면 최상위 댓글 id(서버 재검증)
    try {
      await widget.repository
          .createComment(widget.postId, content: text, parentCommentId: parentId);
      if (!mounted) return;
      _commentCtrl.clear();
      _commentFocus.unfocus(); // 성공 시 키보드 닫음(작성 결과 노출) — 일관 동작
      setState(() {
        _replyTo = null;
        _sending = false;
      });
      await _reload(); // 댓글 목록·수 갱신
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    } on BoardApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false); // ★입력·답글모드·포커스 유지
      AppInfoToast.show(
          context,
          e.code == 'CONTENT_POLICY_VIOLATION'
              ? '부적절한 표현이 포함되어 있어 등록할 수 없습니다.'
              : e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      AppInfoToast.show(context, '댓글을 등록하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _deleteComment(BoardComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('댓글을 삭제할까요?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제',
                  style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.deleteComment(c.id);
      if (!mounted) return;
      await _reload(); // 댓글 목록·수 갱신(최상위 삭제+답글 → placeholder, 대댓글 삭제 → 해당만 제거)
    } on BoardApiException catch (e) {
      if (!mounted) return;
      AppInfoToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppInfoToast.show(context, '댓글을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Widget _replyChip() {
    final c = _replyTo;
    if (c == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      color: AppColors.surfaceCard,
      child: Row(children: [
        const Icon(Icons.subdirectory_arrow_right, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text('${c.author}님에게 답글 작성 중',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _cancelReply,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 16, color: AppColors.textMuted),
          ),
        ),
      ]),
    );
  }

  Widget _commentBar() {
    final canSend = _commentCtrl.text.trim().isNotEmpty && !_sending;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.dividerSoft)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _replyChip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        controller: _commentCtrl,
                        focusNode: _commentFocus,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: _commentMax,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _replyTo != null ? '답글을 입력하세요' : '댓글을 입력하세요',
                          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          border: InputBorder.none,
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canSend ? _sendComment : null,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: canSend ? AppColors.blue : AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(Icons.arrow_upward_rounded,
                              color: canSend ? Colors.white : AppColors.textMuted, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
