import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/auth_image.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import 'models/board_post.dart';
import 'data/board_repository.dart';
import 'board_compose_screen.dart';
import '../trade/report_sheet.dart';

/// 게시판 신고 사유 — 백엔드 VALID_REASONS 중 게시판에 적합한 값만(ABUSIVE_PRICE=시세교란 제외).
const List<Map<String, String>> boardReportReasons = [
  {'code': 'INSULT', 'label': '욕설 / 비방', 'desc': '부적절한 언행'},
  {'code': 'SPAM', 'label': '스팸 / 광고', 'desc': '도배, 광고성 글'},
  {'code': 'FRAUD', 'label': '사기 / 허위', 'desc': '사기 의심, 허위 정보'},
  {'code': 'FAKE', 'label': '조작 / 사칭', 'desc': '위조·사칭 콘텐츠'},
  {'code': 'OTHER', 'label': '기타', 'desc': '직접 사유 입력'},
];

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

class _BoardDetailScreenState extends State<BoardDetailScreen> with WidgetsBindingObserver {
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

  // 좋아요(낙관적 업데이트) — _post 와 분리해 즉시 토글 + 서버 보정/실패 롤백.
  bool _liked = false;
  int _likeCount = 0;
  bool _likeBusy = false; // 진행 중 같은 글 재탭 차단
  bool _changed = false;  // 좋아요/댓글 변경 → 목록 갱신 신호(back pop result)
  String? _deletingCommentId; // 댓글/대댓글 삭제 진행 중(이탈·중복 차단)
  bool _postDeleting = false; // 게시글 삭제 진행 중
  bool _blocking = false; // 사용자 차단 요청 진행 중(이탈·중복 차단)

  // 상태 변경 요청 진행 중 여부 — 진행 중엔 화면 이탈 금지(닫히면 dispose 로 성공 결과·목록 동기화 유실).
  bool get _hasPendingMutation =>
      _likeBusy || _sending || _deletingCommentId != null || _postDeleting || _blocking;

  @override
  void initState() {
    super.initState();
    _commentCtrl.addListener(_onCommentChange);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  // 앱 resume 시 무플래시 재조회 — 관리자 고정/해제 등 백그라운드 중 변경(핀 상태 포함)을 최신화.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _reload();
  }

  void _onCommentChange() {
    if (mounted) setState(() {}); // 전송 버튼 활성/비활성 갱신
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          _liked = p.likedByMe; // 서버 기준 초기화
          _likeCount = p.likeCount;
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
      setState(() {
        _post = p;
        if (!_likeBusy) { // 좋아요 요청 진행 중이면 낙관적 상태 보존
          _liked = p.likedByMe;
          _likeCount = p.likeCount;
        }
      });
    } catch (_) {
      // 재조회 실패는 기존 화면 유지(조용히 무시).
    }
  }

  // 댓글 신고/차단 후 재조회 — 그 작성자가 게시글 작성자이기도 하면 차단으로 상세가 404가 됨.
  // 이 경우 오류 화면에 남기지 않고 pop('changed')로 목록 재조회. 아니면 thread 만 무플래시 갱신.
  Future<void> _reloadOrPopIfGone() async {
    try {
      final p = await widget.repository.fetchDetail(widget.postId);
      if (!mounted) return;
      if (p == null) {
        Navigator.of(context).pop('changed'); // 게시글 작성자=차단 대상 → 상세 불가 → 목록으로
        return;
      }
      setState(() {
        _post = p;
        if (!_likeBusy) {
          _liked = p.likedByMe;
          _likeCount = p.likeCount;
        }
      });
    } catch (_) {
      // 재조회 실패는 기존 화면 유지(조용히 무시).
    }
  }

  // ⋯ 메뉴 — 본인 자유글=수정/삭제 / 비본인·비공식=신고(서버 canReport). 공식글·삭제·숨김은 서버 플래그 false → 미노출.
  List<Widget>? _appBarActions() {
    final p = _post;
    if (p == null || !(p.canEdit || p.canDelete || p.canReport || p.canBlock)) {
      return null;
    }
    return [
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
        color: AppColors.surfaceCard,
        onSelected: (v) {
          if (v == 'edit') _edit(p);
          if (v == 'delete') _delete(p);
          if (v == 'report') _reportPost(p);
          if (v == 'block') _blockPostAuthor(p);
        },
        itemBuilder: (_) => [
          if (p.canEdit)
            const PopupMenuItem(
                value: 'edit',
                child: Text('수정', style: TextStyle(color: AppColors.textPrimary))),
          if (p.canDelete)
            const PopupMenuItem(
                value: 'delete', child: Text('삭제', style: TextStyle(color: AppColors.red))),
          if (p.canReport)
            const PopupMenuItem(
                value: 'report',
                child: Text('신고', style: TextStyle(color: AppColors.textPrimary))),
          if (p.canBlock)
            const PopupMenuItem(
                value: 'block',
                child: Text('사용자 차단', style: TextStyle(color: AppColors.textPrimary))),
        ],
      ),
    ];
  }

  // 게시글 신고 — 공용 ReportSheet 재사용(BOARD_POST, autoBlock=신고 시 작성자 자동 차단).
  // 성공 시 작성자 차단으로 글이 사라지므로 상세를 유지하지 않고 pop('changed') → 목록 재조회(삭제와 동일 패턴).
  Future<void> _reportPost(BoardPost p) async {
    final reported = await ReportSheet.show(context,
        targetType: 'BOARD_POST',
        targetId: p.id,
        targetNoun: '게시글',
        autoBlock: true,
        reasons: boardReportReasons);
    if (!mounted || !reported) return;
    Navigator.of(context).pop('changed'); // imperative pop = PopScope 우회
  }

  // 신고 없이 작성자 차단 — 확인 후 board-post 차단 API(서버가 작성자 해석). 성공 시 콘텐츠 사라짐 → pop('changed').
  Future<void> _blockPostAuthor(BoardPost p) async {
    if (_hasPendingMutation) return;
    if (!await _confirmBlock() || !mounted) return;
    setState(() => _blocking = true);
    try {
      await widget.repository.blockPostAuthor(p.id);
      if (!mounted) return;
      Navigator.of(context).pop('changed'); // imperative pop = PopScope 우회
    } on BoardApiException catch (e) {
      if (!mounted) return;
      setState(() => _blocking = false);
      if (e.statusCode != 401) AppInfoToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _blocking = false);
      AppInfoToast.show(context, '차단하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  // 차단 확인 다이얼로그(게시글·댓글 공용). 차단=true.
  Future<bool> _confirmBlock() async {
    final ok = await AppConfirmDialog.show(
      context,
      title: '사용자를 차단할까요?',
      message: '이 사용자를 차단하면 해당 사용자의 게시글과 댓글이 표시되지 않습니다.\n차단 목록에서 언제든 해제할 수 있습니다.',
      cancelLabel: '취소',
      confirmLabel: '차단',
      destructive: true,
    );
    return ok == true;
  }

  Future<void> _edit(BoardPost p) async {
    final updated = await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => BoardComposeScreen(repository: widget.repository, editing: p)));
    if (updated != null && mounted) _load(); // 수정 성공 → 상세 갱신
  }

  Future<void> _delete(BoardPost p) async {
    if (_hasPendingMutation) return; // 다른 변경 진행 중 — 중복 다이얼로그/요청 방지
    final ok = await AppConfirmDialog.show(
      context,
      title: '글을 삭제할까요?',
      message: '삭제한 글은 복구할 수 없어요.',
      cancelLabel: '취소',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _postDeleting = true);
    try {
      await widget.repository.deletePost(p.id);
      if (!mounted) return;
      Navigator.of(context).pop('deleted'); // force pop(성공) — PopScope 우회. 목록 새로고침 신호
    } on BoardApiException catch (e) {
      if (!mounted) return;
      setState(() => _postDeleting = false);
      if (e.statusCode != 401) AppInfoToast.show(context, e.message); // 401=전역 lifecycle(로그아웃)
    } catch (_) {
      if (!mounted) return;
      setState(() => _postDeleting = false);
      AppInfoToast.show(context, '삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleType = (_post ?? widget.summary)?.type;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // ★상태 변경 요청(좋아요·댓글 작성/삭제·게시글 삭제) 진행 중엔 닫지 않음 — 닫으면 dispose 로
        //   성공 결과(_changed/목록 동기화)가 유실됨. AppBar 뒤로·iOS swipe-back 모두 PopScope(canPop:false)
        //   경로라 함께 막힘. 완료/실패 후 재시도 가능.
        if (_hasPendingMutation) return;
        Navigator.of(context).pop(_changed ? 'changed' : null); // 좋아요/댓글 변경 → 목록 갱신
      },
      child: Scaffold(
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
      ),
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

    // ★1.0.4: 공식글(공지/이벤트/패치)도 자유글과 동일하게 좋아요·댓글·대댓글·입력바 노출.
    //   (게시글 자체 수정·삭제만 관리자 전용 — 그건 서버 canEdit/canDelete 로 게이트)
    final content = ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _header(post),
        const SizedBox(height: 18),
        Text(post.body,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, height: 1.6)),
        _imageGallery(post), // 첨부 이미지(있으면) — 공지·자유 공통, 본문 아래
        const SizedBox(height: 18),
        _engagementRow(post), // ♥ 좋아요 토글 · 댓글 수 (공식글 포함)
        const SizedBox(height: 16),
        const Divider(height: 1, color: AppColors.divider),
        const SizedBox(height: 12),
        ...post.comments.map(_commentTile),
        if (post.comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: Text('아직 댓글이 없어요',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13))),
          ),
      ],
    );

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
            _pinBadge(),
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

  // ★고정 표시 — 노란 압정 대신 절제된 파란 '고정' 배지(앱 배지 체계 재사용).
  Widget _pinBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.push_pin, size: 10, color: AppColors.blueLight),
        SizedBox(width: 3),
        Text('고정',
            style: TextStyle(color: AppColors.blueLight, fontSize: 9.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  // 본문 아래 인게이지먼트: 좋아요(토글) + 댓글 수. ★1.0.4 공식글 포함 모든 노출글에 노출. 활성 좋아요=파란색.
  Widget _engagementRow(BoardPost post) {
    return Row(children: [
      if (post.type.isBoardVisible) ...[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _likeBusy ? null : _toggleLike,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_liked ? Icons.favorite : Icons.favorite_border,
                  size: 20, color: _liked ? AppColors.blue : AppColors.textMuted),
              const SizedBox(width: 5),
              Text('$_likeCount',
                  style: TextStyle(
                      color: _liked ? AppColors.blue : AppColors.textSecondary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(width: 16),
      ],
      Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.chat_bubble_outline_rounded, size: 17, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text('${post.commentCount}',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600)),
      ]),
    ]);
  }

  // 낙관적 좋아요 토글: 즉시 반영 → 서버 응답으로 보정 / 실패 시 정확 롤백. 진행 중 재탭 차단.
  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final wasLiked = _liked;
    final wasCount = _likeCount;
    setState(() {
      _likeBusy = true;
      _liked = !wasLiked;
      _likeCount = wasLiked ? (wasCount > 0 ? wasCount - 1 : 0) : wasCount + 1; // 0 미만 금지
    });
    try {
      final res = wasLiked
          ? await widget.repository.unlikePost(widget.postId)
          : await widget.repository.likePost(widget.postId);
      if (!mounted) return;
      setState(() {
        _liked = res.likedByMe; // 서버 최종값 보정
        _likeCount = res.likeCount;
        _likeBusy = false;
        _changed = true; // 목록 반영
      });
    } on BoardApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked; // 정확 롤백
        _likeCount = wasCount;
        _likeBusy = false;
      });
      if (e.statusCode != 401) AppInfoToast.show(context, _likeError(e)); // 401=전역 lifecycle
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likeCount = wasCount;
        _likeBusy = false;
      });
      AppInfoToast.show(context, '잠시 후 다시 시도해 주세요.');
    }
  }

  String _likeError(BoardApiException e) {
    switch (e.statusCode) {
      case 401:
        return '로그인이 필요해요.';
      case 403:
        return '이 글은 좋아요할 수 없어요.';
      case 404:
        return '삭제되었거나 존재하지 않는 글이에요.';
      default:
        return e.message;
    }
  }

  static const _commentMax = 2000; // 서버 COMMENT_MAX 와 동일

  // 댓글/대댓글 액션(답글·삭제·신고). 플래그(canReply+target / canDelete / canReport)로 노출 제어.
  // 삭제 placeholder·본인·공식 작성 댓글은 서버 플래그 false → 해당 버튼 자동 미노출.
  Widget _commentActions(BoardComment c) {
    final canReply = c.canReply && c.replyTargetCommentId != null;
    final items = <Widget>[
      if (canReply) _commentAction('답글', () => _startReply(c)),
      if (c.canDelete) _commentAction('삭제', () => _deleteComment(c), color: AppColors.red),
      if (c.canReport) _commentAction('신고', () => _reportComment(c)),
      if (c.canBlock) _commentAction('차단', () => _blockCommentAuthor(c)),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          items[i],
        ],
      ]),
    );
  }

  // 댓글/대댓글 신고 — 공용 ReportSheet(BOARD_COMMENT, autoBlock). 성공 시 작성자 차단 → 해당 작성자 댓글이
  // 서버 필터로 thread 에서 사라짐. 상세는 유지하고 thread 만 무플래시 재조회.
  Future<void> _reportComment(BoardComment c) async {
    final reported = await ReportSheet.show(context,
        targetType: 'BOARD_COMMENT',
        targetId: c.id,
        targetNoun: '댓글',
        autoBlock: true,
        reasons: boardReportReasons);
    if (!mounted || !reported) return;
    _changed = true; // 목록 댓글 수 갱신 신호
    await _reloadOrPopIfGone(); // 작성자=게시글 작성자면 차단으로 상세 404 → pop('changed')
  }

  // 댓글 작성자 차단(신고 없이) — 확인 후 board-comment 차단 API. 성공 시 작성자 댓글이 서버 필터로 thread 에서
  // 사라짐. 상세는 유지하고 thread 만 무플래시 재조회.
  Future<void> _blockCommentAuthor(BoardComment c) async {
    if (_hasPendingMutation) return;
    if (!await _confirmBlock() || !mounted) return;
    setState(() => _blocking = true);
    try {
      await widget.repository.blockCommentAuthor(c.id);
      if (!mounted) return;
      setState(() => _blocking = false);
      _changed = true;
      await _reloadOrPopIfGone(); // 작성자=게시글 작성자면 차단으로 상세 404 → pop('changed')
    } on BoardApiException catch (e) {
      if (!mounted) return;
      setState(() => _blocking = false);
      if (e.statusCode != 401) AppInfoToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _blocking = false);
      AppInfoToast.show(context, '차단하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
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
        _changed = true; // 목록 댓글 수 갱신 신호
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
      if (e.statusCode == 401) return; // 401=전역 lifecycle(로그아웃)이 처리
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
    if (_hasPendingMutation) return; // 다른 변경 진행 중 — 중복 다이얼로그/요청 방지
    final ok = await AppConfirmDialog.show(
      context,
      title: '댓글을 삭제할까요?',
      message: '삭제한 댓글은 복구할 수 없어요.',
      cancelLabel: '취소',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _deletingCommentId = c.id);
    try {
      await widget.repository.deleteComment(c.id);
      if (!mounted) return;
      _changed = true; // 목록 댓글 수 갱신 신호(reload 전 기록 — 이탈해도 유실 안 됨)
      await _reload(); // 댓글 목록·수 갱신(최상위 삭제+답글 → placeholder, 대댓글 삭제 → 해당만 제거)
    } on BoardApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != 401) AppInfoToast.show(context, e.message); // 401=전역 lifecycle
    } catch (_) {
      if (!mounted) return;
      AppInfoToast.show(context, '댓글을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _deletingCommentId = null);
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

  /// 첨부 이미지 갤러리 — 본문 아래 full-width 세로 스택(4:3 cover). 탭 → 전체화면 스와이프·확대.
  Widget _imageGallery(BoardPost post) {
    if (post.images.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          for (int i = 0; i < post.images.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _openGallery(post, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  height: 380, // 높이 상한(고정). contain 이라 세로형 카드도 잘리지 않고 레터박스로 표시.
                  color: AppColors.surfaceCard, // 이미지 주변 빈 공간 배경
                  child: AuthImage(
                    url: post.images[i].url,
                    fit: BoxFit.contain, // ★원본 비율 유지 — 카드 세로사진 위아래 잘림 방지
                    errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.image_outlined,
                            color: AppColors.textMuted, size: 28)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openGallery(BoardPost post, int index) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _BoardGalleryViewer(images: post.images, initialIndex: index),
    ));
  }
}

/// 전체화면 이미지 뷰어 — 스와이프(PageView) + 핀치 확대(InteractiveViewer) + 닫기/페이지 표시.
class _BoardGalleryViewer extends StatefulWidget {
  final List<BoardPostImage> images;
  final int initialIndex;
  const _BoardGalleryViewer({required this.images, required this.initialIndex});

  @override
  State<_BoardGalleryViewer> createState() => _BoardGalleryViewerState();
}

class _BoardGalleryViewerState extends State<_BoardGalleryViewer> {
  late final PageController _pc = PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: AuthImage(
                  url: widget.images[i].url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    if (widget.images.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Text('${_current + 1} / ${widget.images.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
