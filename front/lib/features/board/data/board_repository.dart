import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../models/board_post.dart';

/// 게시판 API 논리 실패 — HTTP 200 이어도 `ReturnData.status != "success"` 인 경우 포함.
/// message/code 를 보존해 화면이 사용자에게 표시할 수 있게 한다.
class BoardApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  const BoardApiException(this.message, {this.code, this.statusCode});
  @override
  String toString() => 'BoardApiException(code=$code, status=$statusCode): $message';
}

/// 게시판 응답 파싱 실패 — data null·형식 오류·알 수 없는 type·잘못된 날짜 등.
/// ★조용히 빈 목록/기본값으로 바꾸지 않고 이 예외로 올려 화면이 "오류+재시도"를 보이게 한다.
class BoardParseException implements Exception {
  final String message;
  const BoardParseException(this.message);
  @override
  String toString() => 'BoardParseException: $message';
}

/// `ReturnData.status` 검사. fail 이면(HTTP 200 이어도) BoardApiException.
void _requireSuccess(Map<String, dynamic> res) {
  if (res['status'] != 'success') {
    throw BoardApiException(
      (res['message'] as String?) ?? '요청을 처리하지 못했어요.',
      code: res['code'] as String?,
    );
  }
}

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

  /// ReturnData 맵 → 목록 결과. **네트워크와 분리(순수 함수, 테스트 가능)**.
  /// status 검사 + data/content 형식 검사 + 항목 파싱오류 전파(빈 목록 위장 금지).
  static BoardListResult parse(Map<String, dynamic> res,
      {int fallbackPage = 0, int fallbackSize = 20}) {
    _requireSuccess(res);
    final data = res['data'];
    if (data is! Map) throw const BoardParseException('목록 응답 data 형식 오류');
    final rawList = data['content'];
    if (rawList is! List) throw const BoardParseException('목록 content 형식 오류');

    final List<BoardPost> posts;
    try {
      posts = rawList
          .map((e) => BoardPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on FormatException catch (e) {
      throw BoardParseException(e.message);
    } catch (e) {
      throw BoardParseException('목록 항목 파싱 오류: $e');
    }

    return BoardListResult(
      posts: posts,
      page: (data['page'] as num?)?.toInt() ?? fallbackPage,
      size: (data['size'] as num?)?.toInt() ?? fallbackSize,
      totalPages: (data['totalPages'] as num?)?.toInt() ?? 1,
      totalElements: (data['totalElements'] as num?)?.toInt() ?? posts.length,
    );
  }
}

/// 상세 응답(`ReturnData<BoardPostDetailDto>`) → BoardPost. status 검사 + 파싱오류 전파.
BoardPost parseBoardDetail(Map<String, dynamic> res) {
  _requireSuccess(res);
  final data = res['data'];
  if (data is! Map) throw const BoardParseException('상세 응답 data 형식 오류');
  try {
    return BoardPost.fromJson(Map<String, dynamic>.from(data));
  } on FormatException catch (e) {
    throw BoardParseException(e.message);
  } catch (e) {
    throw BoardParseException('상세 파싱 오류: $e');
  }
}

/// 게시판 읽기 API. 백엔드는 4xx 에 ResponseStatusException(실 HTTP 상태) → Dio throw.
/// 전역 ApiClient 인터셉터가 401/5xx/네트워크 공통 토스트 처리. 화면은 예외로 상태 분기.
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
    return BoardListResult.parse(res, fallbackPage: page, fallbackSize: size);
  }

  /// 상세(댓글 1단 트리 포함). 미존재/삭제/숨김(404) → null. 그 외는 예외 전파.
  Future<BoardPost?> fetchDetail(String postId) async {
    try {
      final res = await ApiClient.get('/api/board/posts/$postId');
      return parseBoardDetail(res);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
