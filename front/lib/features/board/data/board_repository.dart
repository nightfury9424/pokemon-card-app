import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../models/board_post.dart';

/// 게시판 목록 응답(BoardPageDto) — 페이지네이션 메타 포함.
class BoardListResult {
  final List<BoardPost> posts;
  final int page;
  final int size;
  final int totalPages;
  final int totalElements;

  const BoardListResult({
    required this.posts,
    required this.page,
    required this.size,
    required this.totalPages,
    required this.totalElements,
  });

  bool get hasMore => page + 1 < totalPages;
}

/// 게시판 읽기 API. 백엔드 `ReturnData<BoardPageDto>` / `ReturnData<BoardPostDetailDto>` 파싱.
///
/// 성공판정 = HTTP 2xx + `res['data']`. 백엔드 board 는 4xx 에 ResponseStatusException 을 써서
/// 실제 HTTP 상태(404/403/401)를 반환 → Dio 가 DioException throw → 호출 화면이 상태 처리.
/// (전역 ApiClient 인터셉터가 401/5xx/네트워크는 공통 토스트 처리.)
class BoardRepository {
  const BoardRepository();

  /// 목록. section/type 필터 + 페이지. 핀 우선 정렬은 서버 책임.
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    int page = 0,
    int size = 20,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (section != null) params['section'] = section;
    if (type != null) params['type'] = type;

    final res = await ApiClient.get('/api/board/posts', params: params);
    final data = Map<String, dynamic>.from((res['data'] as Map?) ?? const {});
    final content = ((data['content'] as List?) ?? const [])
        .map((e) => BoardPost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return BoardListResult(
      posts: content,
      page: (data['page'] as num?)?.toInt() ?? page,
      size: (data['size'] as num?)?.toInt() ?? size,
      totalPages: (data['totalPages'] as num?)?.toInt() ?? 1,
      totalElements: (data['totalElements'] as num?)?.toInt() ?? content.length,
    );
  }

  /// 상세(댓글 1단 트리 포함). 미존재/삭제/숨김(404) → null. 그 외 오류는 rethrow.
  Future<BoardPost?> fetchDetail(String postId) async {
    try {
      final res = await ApiClient.get('/api/board/posts/$postId');
      final data = res['data'];
      if (data is! Map) return null;
      return BoardPost.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
