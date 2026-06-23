import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import 'models/board_post.dart';
import 'data/board_repository.dart';
import 'board_detail_screen.dart';
import 'board_compose_screen.dart';

/// 게시판 — **공지 | 자유** 2탭(기본=자유). 공지=section=official(읽기전용·관리자 작성),
/// 자유=type=free(로그인 작성·댓글·좋아요). 서버 페이지네이션·핀 우선 정렬.
class BoardScreen extends StatefulWidget {
  /// 주입 가능(테스트용 fake). 운영 기본 = const BoardRepository().
  final BoardRepository repository;
  const BoardScreen({super.key, this.repository = const BoardRepository()});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  static const _pageSize = 20;

  int _tab = 1; // 0 = 공지(official), 1 = 자유(free). 기본 = 자유.
  final ScrollController _scroll = ScrollController();

  List<BoardPost> _posts = const [];
  bool _loading = true;
  Object? _error;
  int _page = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _reqToken = 0; // 탭 전환/새로고침 경쟁 방지(늦게 온 응답 폐기)
  bool _pendingScrollReset = false; // 탭 전환 시 목록 최상단 복귀

  bool get _isNotice => _tab == 0;
  String? get _section => _isNotice ? 'official' : null;
  String? get _type => _isNotice ? null : 'free';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_reqToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.repository.fetchList(
          section: _section, type: _type, page: 0, size: _pageSize);
      if (!mounted || token != _reqToken) return; // 늦게 온 이전 탭 응답 폐기
      setState(() {
        _posts = r.posts;
        _page = r.page;
        _hasMore = r.hasMore;
        _loading = false;
      });
      if (_pendingScrollReset) {
        _pendingScrollReset = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(0); // 탭 전환 후 최상단
        });
      }
    } catch (e) {
      if (!mounted || token != _reqToken) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _error != null) return;
    final token = _reqToken; // 같은 탭/세션 동안만 유효
    setState(() => _loadingMore = true);
    try {
      final r = await widget.repository.fetchList(
          section: _section, type: _type, page: _page + 1, size: _pageSize);
      if (!mounted || token != _reqToken) return;
      setState(() {
        _posts = [..._posts, ...r.posts];
        _page = r.page;
        _hasMore = r.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      // 추가 로드 실패는 목록 유지(전역 핸들러가 토스트). 다음 스크롤에 재시도 가능.
      setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  void _switchTab(int t) {
    if (_tab == t) return;
    _pendingScrollReset = true;
    setState(() {
      _tab = t;
      _posts = const [];
      _hasMore = false;
      _loadingMore = false;
    });
    _load();
  }

  // 자유 탭 글쓰기 FAB → root navigator 전체화면 작성. 성공 시 목록 새로고침.
  Future<void> _openCompose() async {
    final created = await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => BoardComposeScreen(repository: widget.repository)));
    if (created != null && mounted) _load();
  }

  // 상세 진입. 상세에서 수정·삭제(비-null 결과) 발생 시 목록 갱신.
  Future<void> _openDetail(BoardPost post) async {
    final changed = await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BoardDetailScreen(
            postId: post.id, summary: post, repository: widget.repository)));
    if (changed != null && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
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
      // 자유 탭만 글쓰기 FAB(공지는 관리자 웹 전용 = 앱 작성 버튼 없음).
      floatingActionButton: _isNotice
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.blue,
              onPressed: _openCompose,
              icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
              label: const Text('글쓰기',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
      body: Column(
        children: [
          _tabBar(),
          const SizedBox(height: 4),
          Expanded(child: _body(fabBottomInset)),
        ],
      ),
    );
  }

  Widget _tabBar() {
    Widget tab(String label, int idx) {
      final sel = _tab == idx;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchTab(idx),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: sel ? AppColors.blue : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                  color: sel ? AppColors.textPrimary : AppColors.textMuted,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14.5,
                )),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerSoft, width: 1)),
      ),
      child: Row(children: [tab('공지', 0), tab('자유', 1)]),
    );
  }

  Widget _body(double fabBottomInset) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_error != null) {
      return _errorState();
    }
    if (_posts.isEmpty) {
      // 빈 상태도 당겨서 새로고침 가능하게 스크롤 가능한 영역으로.
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.blue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: Center(
                child: Text(_isNotice ? '등록된 공지가 없어요' : '아직 글이 없어요',
                    style: const TextStyle(color: AppColors.textMuted)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.blue,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 4, 16, fabBottomInset),
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, i) => i < _posts.length - 1
            ? const Divider(height: 1, color: AppColors.dividerSoft)
            : const SizedBox.shrink(),
        itemBuilder: (_, i) {
          if (i >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2))),
            );
          }
          return PostRow(post: _posts[i], onTap: () => _openDetail(_posts[i]));
        },
      ),
    );
  }

  Widget _errorState() {
    final msg = _error is BoardApiException
        ? (_error as BoardApiException).message
        : '목록을 불러오지 못했어요.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(msg, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
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
}

class PostRow extends StatelessWidget {
  final BoardPost post;
  final VoidCallback? onTap; // 목록에서 주입(상세 진입 + 변경 시 새로고침). null=무동작(반응형 테스트용).
  const PostRow({super.key, required this.post, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
                  Text(boardRelativeTime(post.createdAt),
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
                    // 좋아요는 자유글 전용 — 표시만(토글은 상세에서). 내가 누른 글은 채운 하트.
                    if (post.type == BoardType.free && post.likeCount > 0)
                      _meta(post.likedByMe ? Icons.favorite : Icons.favorite_border, post.likeCount,
                          color: post.likedByMe ? AppColors.red : null),
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

  Widget _meta(IconData icon, int n, {Color? color}) {
    final c = color ?? AppColors.textMuted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: c),
      const SizedBox(width: 3),
      Text('$n', style: TextStyle(color: c, fontSize: 11.5)),
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
