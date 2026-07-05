import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../board/board_detail_screen.dart';
import '../board/board_screen.dart' show PostRow;
import '../board/data/board_repository.dart';
import '../board/models/board_post.dart';

/// MY > 커뮤니티 > 내 활동.
/// 2탭(내가 쓴 글 / 내가 댓글 단 글). 기존 게시판 row(PostRow)·상세(BoardDetailScreen) 재사용.
/// 정렬·dedup·삭제/숨김/차단 제외는 서버(/api/board/me/*) 책임. 댓글 위치 자동 스크롤은 2차(여기선 상세 진입까지).
class MyActivityScreen extends StatelessWidget {
  final BoardRepository repository;
  const MyActivityScreen({super.key, this.repository = const BoardRepository()});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          title: const Text('내 활동'),
          bottom: const TabBar(
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.blue,
            indicatorWeight: 2.5,
            labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            tabs: [Tab(text: '내가 쓴 글'), Tab(text: '내가 댓글 단 글')],
          ),
        ),
        body: TabBarView(
          children: [
            _ActivityTab(
              key: const PageStorageKey('myPosts'),
              fetcher: repository.fetchMyPosts,
              emptyMessage: '아직 작성한 글이 없어요',
              repository: repository,
            ),
            _ActivityTab(
              key: const PageStorageKey('myCommented'),
              fetcher: repository.fetchMyCommentedPosts,
              emptyMessage: '아직 댓글을 남긴 글이 없어요',
              repository: repository,
            ),
          ],
        ),
      ),
    );
  }
}

typedef _Fetcher = Future<BoardListResult> Function({int page, int size});

class _ActivityTab extends StatefulWidget {
  final _Fetcher fetcher;
  final String emptyMessage;
  final BoardRepository repository;
  const _ActivityTab({
    super.key,
    required this.fetcher,
    required this.emptyMessage,
    required this.repository,
  });

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 20;
  final ScrollController _scroll = ScrollController();
  List<BoardPost> _posts = const [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true; // 탭 전환해도 재조회 안 함

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

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.fetcher(page: 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _posts = r.posts;
        _page = r.page;
        _hasMore = r.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _error != null) return;
    setState(() => _loadingMore = true);
    try {
      final r = await widget.fetcher(page: _page + 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _posts = [..._posts, ...r.posts];
        _page = r.page;
        _hasMore = r.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openDetail(BoardPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardDetailScreen(
          postId: post.id,
          summary: post,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) _load(); // 복귀 시 갱신(삭제·수정·댓글 반영)
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAlive
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppColors.blue, strokeWidth: 2.4));
    }
    if (_error != null) {
      // 에러 branch(로드 실패) — 빈 상태와 구분 유지, 기존 _load 재시도 그대로.
      return EmptyState.networkError(onRetry: _load);
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.blue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: EmptyState(
                icon: Icons.history_rounded,
                title: widget.emptyMessage,
                description: '게시판에 글이나 댓글을 남겨보세요',
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
        padding: EdgeInsets.fromLTRB(
            16, 4, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
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
                  child: CircularProgressIndicator(
                      color: AppColors.blue, strokeWidth: 2.2),
                ),
              ),
            );
          }
          return PostRow(post: _posts[i], onTap: () => _openDetail(_posts[i]));
        },
      ),
    );
  }
}
