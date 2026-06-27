import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import 'models/board_post.dart';
import 'data/board_repository.dart';
import 'board_detail_screen.dart';
import 'board_compose_screen.dart';
import 'models/board_filter.dart';
import '../../core/widgets/auth_image.dart';

/// 재조회한 페이지들을 순서대로 병합 + postId 중복 제거(핀 이동으로 페이지 간 옮겨진 글 중복 방지). 테스트 가능.
List<BoardPost> mergeBoardPages(List<List<BoardPost>> pages) {
  final out = <BoardPost>[];
  final seen = <String>{};
  for (final page in pages) {
    for (final p in page) {
      if (seen.add(p.id)) out.add(p);
    }
  }
  return out;
}

/// 게시판 — 전체|공지|이벤트|패치노트|자유|거래후기|사기주의 7탭(기본=전체).
/// 공식(공지/이벤트/패치)=관리자 작성·읽기전용, 사용자(자유/거래후기/사기주의)=작성·댓글·좋아요. 서버 페이지네이션·핀 우선.
class BoardScreen extends StatefulWidget {
  /// 주입 가능(테스트용 fake). 운영 기본 = const BoardRepository().
  final BoardRepository repository;

  /// 진입 필터 — ★의미 기반(기본=전체). 홈 공지배너 › 는 BoardFilter.notice 로 진입.
  final BoardFilter initialFilter;
  const BoardScreen({
    super.key,
    this.repository = const BoardRepository(),
    this.initialFilter = BoardFilter.all,
  });

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> with WidgetsBindingObserver {
  static const _pageSize = 20;

  late BoardFilter _filter; // initState 에서 widget.initialFilter 로 초기화.
  final ScrollController _scroll = ScrollController();

  List<BoardPost> _posts = const [];
  bool _loading = true;
  Object? _error;
  int _page = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _reqToken = 0; // 탭 전환/새로고침 경쟁 방지(늦게 온 응답 폐기)
  bool _pendingScrollReset = false; // 탭 전환 시 목록 최상단 복귀

  // ★제목 검색(현재 탭 범위). _query=활성 검색어(trim·빈=미적용). debounce 300ms·최신요청만(reqToken).
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searchMode = false; // 검색 입력창 열림
  String _query = '';
  Timer? _debounce;
  static const _maxQueryLen = 50;

  String? get _section => _filter.querySection; // 공지=official(공지/이벤트/패치 통합)
  String? get _type => _filter.queryType; // 자유=free, 전체=null(서버가 노출타입만)

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── 제목 검색 ──
  void _startSearch() => setState(() => _searchMode = true);

  // 검색 종료 + 검색어 있었으면 원래 목록 복원.
  void _exitSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    final had = _query.isNotEmpty;
    setState(() {
      _searchMode = false;
      _query = '';
    });
    if (had) _load(); // 검색어 제거 → 원래 목록 복원
  }

  // 입력 debounce(300ms). 같은 검색어면 무시. 최신요청만 reqToken 으로 반영(오래된 응답 폐기).
  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      var q = raw.trim();
      if (q.length > _maxQueryLen) q = q.substring(0, _maxQueryLen);
      if (q == _query) return;
      setState(() => _query = q);
      _load();
    });
  }

  // 앱 resume 시 무플래시 재조회 — 관리자 고정/해제 등 백그라운드 중 변경(핀 우선순위 포함)을 최신화.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _silentReload();
  }

  Future<void> _load() async {
    final token = ++_reqToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.repository.fetchList(
        section: _section,
        type: _type,
        q: _query.isEmpty ? null : _query,
        page: 0,
        size: _pageSize,
      );
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

  // 무플래시 재조회 — 스피너 전환 없이 목록 갱신. resume·목록 복귀 시 핀/내용 최신화.
  // ★현재 로드한 페이지 범위(0.._page)를 모두 재조회·병합 → 페이지네이션 보존(첫 20개로 축소 방지).
  //   순서 병합 + postId 중복 제거(핀 이동으로 페이지 간 옮겨진 글 중복 방지) + 토큰으로 loadMore 경쟁 차단.
  Future<void> _silentReload() async {
    final token = ++_reqToken; // in-flight load/loadMore 무효화
    final pageCount = _page + 1;
    try {
      final pages = <List<BoardPost>>[];
      BoardListResult? last;
      for (int p = 0; p < pageCount; p++) {
        final r = await widget.repository.fetchList(
          section: _section,
          type: _type,
          q: _query.isEmpty ? null : _query, // ★검색 중 상세 복귀 시 검색 결과 보존(기존 _silentReload 가 q 누락 → 전체목록 복원 버그)
          page: p,
          size: _pageSize,
        );
        if (!mounted || token != _reqToken) return; // 더 새 요청·언마운트 → 폐기(기존 유지)
        pages.add(r.posts);
        last = r;
      }
      if (!mounted || token != _reqToken || last == null) return;
      setState(() {
        _posts = mergeBoardPages(pages);
        _page = last!.page;
        _hasMore = last.hasMore;
        _error = null;
      });
    } catch (_) {
      // 재조회 실패는 기존 목록 유지(조용히 무시).
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _error != null) return;
    final token = _reqToken; // 같은 탭/세션 동안만 유효
    setState(() => _loadingMore = true);
    try {
      final r = await widget.repository.fetchList(
        section: _section,
        type: _type,
        q: _query.isEmpty ? null : _query,
        page: _page + 1,
        size: _pageSize,
      );
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

  void _switchFilter(BoardFilter f) {
    if (_filter == f) return;
    _pendingScrollReset = true;
    setState(() {
      _filter = f;
      _posts = const [];
      _hasMore = false;
      _loadingMore = false;
    });
    _load();
  }

  // 글쓰기 FAB → root navigator 전체화면 작성. 현재 탭이 카테고리면 그 타입 사전선택(전체=자유). 성공 시 목록 새로고침.
  Future<void> _openCompose() async {
    final created = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => BoardComposeScreen(
          repository: widget.repository,
          initialType: _filter.composeType,
        ),
      ),
    );
    if (created != null && mounted) _load();
  }

  // 상세 진입. 상세에서 수정·삭제(비-null 결과) 발생 시 목록 갱신.
  Future<void> _openDetail(BoardPost post) async {
    FocusScope.of(context).unfocus(); // ★상세 진입 전 키보드 닫기 — 검색 모드·검색어·결과는 유지, 복귀 시 자동 재오픈 안 함.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardDetailScreen(
          postId: post.id,
          summary: post,
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted) return;
    // 복귀 시 무플래시 갱신 — 삭제·수정 반영 + 관리자 핀 변경 최신화(변경 없어도 핀 동기화).
    _silentReload();
  }

  @override
  Widget build(BuildContext context) {
    final fabBottomInset =
        AppDimens.bottomContentInsetForExtendedFab +
        MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        // 검색 모드: 좌측 ← 가 검색 종료(_exitSearch). 우측 닫기 X 제거 → 검색창 X 중복 해소.
        leading: _searchMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: _exitSearch,
                tooltip: '검색 닫기',
              )
            : null,
        title: _searchMode
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                maxLines: 1, // ★항상 한 줄
                textAlignVertical: TextAlignVertical.center, // ★입력·힌트·X 버튼 수직 중앙(2줄처럼 보이는 현상 제거)
                textInputAction: TextInputAction.search,
                maxLength: _maxQueryLen,
                buildCounter: (_, {required int currentLength, required bool isFocused, int? maxLength}) => null,
                onChanged: (raw) {
                  setState(() {}); // clear 아이콘 표시 갱신
                  _onSearchChanged(raw);
                },
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: '제목 검색',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 16),
                  border: InputBorder.none,
                  isCollapsed: true,
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _debounce?.cancel();
                            _searchCtrl.clear();
                            if (_query.isNotEmpty) {
                              setState(() => _query = '');
                              _load(); // 검색어 제거 → 원래 목록 복원(즉시)
                            } else {
                              setState(() {});
                            }
                          },
                          child: const Icon(Icons.clear, size: 18, color: AppColors.textMuted),
                        ),
                ),
              )
            : const Text(
                '게시판',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
        // 검색 모드에선 닫기 X 미노출(좌측 ← 가 종료) — 검색창의 입력 clear X 와 중복 방지.
        actions: _searchMode
            ? const []
            : [
                IconButton(
                  icon: const Icon(Icons.search, color: AppColors.textPrimary, size: 22),
                  onPressed: _startSearch,
                  tooltip: '제목 검색',
                ),
              ],
      ),
      // 전체 + 사용자 카테고리(자유/거래후기/사기주의)만 글쓰기 FAB. 공식(공지/이벤트/패치)=관리자 웹 전용.
      floatingActionButton: _filter.canWrite
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.blue,
              onPressed: _openCompose,
              elevation: 2,
              icon: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
              label: const Text('글쓰기',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            )
          : null,
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
    // 목업 pill 탭 — 선택=파란 외곽선·파란 텍스트·옅은 파란 배경 / 비선택=어두운 배경·약한 테두리.
    Widget tab(BoardFilter f) {
      final sel = _filter == f;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.5),
        child: GestureDetector(
          onTap: () => _switchFilter(f),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              color: sel
                  ? AppColors.blueDeep.withValues(alpha: 0.30)
                  : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: sel ? AppColors.blue : AppColors.divider,
                width: sel ? 1.4 : 1,
              ),
            ),
            child: Text(
              f.label,
              style: TextStyle(
                color: sel ? AppColors.blueLight : AppColors.textSecondary,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity, // ★전체폭 고정 — 탭이 적어도(3개) 왼쪽정렬·전체폭 구분선 유지(가운데 모임 방지)
      padding: const EdgeInsets.fromLTRB(13, 6, 13, 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.dividerSoft, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: BoardFilter.values.map(tab).toList()),
      ),
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
                child: Text(
                  _query.isNotEmpty
                      ? "'$_query' 검색 결과가 없어요"
                      : _filter == BoardFilter.all
                          ? '아직 글이 없어요'
                          : '등록된 ${_filter.label} 게시글이 없어요',
                  style: const TextStyle(color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
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
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
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
          Text(
            msg,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _load,
            child: const Text(
              '다시 시도',
              style: TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w700,
              ),
            ),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Row(
              children: [
                _typeChip(post.type),
                if (post.isPinned) ...[
                  const SizedBox(width: 6),
                  _pinBadge(),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              post.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              post.body.replaceAll('\n', ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 9),
            // 작성자·시간 한 줄 → 아래 보조 메타(좋아요·댓글·조회)를 텍스트형(토스식, 아이콘 제거).
            Row(
              children: [
                Flexible(
                  child: Text(
                    post.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const _Dot(),
                Text(
                  boardRelativeTime(post.createdAt),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '좋아요 ${post.likeCount} · 댓글 ${post.commentCount} · 조회 ${post.viewCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
                ),
              ),
            if (post.thumbnailUrl != null) ...[
              const SizedBox(width: 12),
              _thumbnail(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumbnail() {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AuthImage(
              url: post.thumbnailUrl!,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 80,
                height: 80,
                color: AppColors.surfaceCard,
                child: const Icon(Icons.image_outlined, color: AppColors.textMuted, size: 22),
              ),
            ),
          ),
          if (post.imageCount > 1)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.collections, size: 10, color: Colors.white),
                    const SizedBox(width: 3),
                    Text('${post.imageCount}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (type.isAdmin) ...[
            Icon(type.icon, size: 11.5, color: type.color),
            const SizedBox(width: 4),
          ],
          Text(
            type.label,
            style: TextStyle(
              color: type.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ★고정 표시 — 노란 압정 대신 절제된 파란 '고정' 배지(상세와 동일 규칙).
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
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      '·',
      style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
    ),
  );
}
