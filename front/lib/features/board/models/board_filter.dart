import 'board_post.dart';

/// 게시판 탭/필터 — ★최종 IA: **전체 | 공지 | 자유** 3탭만(기본=전체).
/// 공지 = official 섹션(공지/이벤트/패치노트를 한 탭에 통합, 게시글 배지로 구분, 관리자만 작성).
/// 자유 = free 타입(사용자 작성, 카테고리 없음). 전체 = 공지 3종 + 자유 통합.
/// (이전 7탭[이벤트·패치노트·거래후기·사기주의]은 폐기. 사용자 작성은 free 하나뿐.)
enum BoardFilter { all, notice, free }

extension BoardFilterX on BoardFilter {
  String get label {
    switch (this) {
      case BoardFilter.all:
        return '전체';
      case BoardFilter.notice:
        return '공지';
      case BoardFilter.free:
        return '자유';
    }
  }

  /// 서버 조회 section. 공지=official(공지/이벤트/패치 통합), 그 외 null.
  String? get querySection {
    switch (this) {
      case BoardFilter.notice:
        return 'official';
      default:
        return null;
    }
  }

  /// 서버 조회 type. 자유=free, 그 외 null(전체=미필터·서버가 노출타입만, 공지=section 필터).
  String? get queryType {
    switch (this) {
      case BoardFilter.free:
        return 'free';
      default:
        return null;
    }
  }

  /// 글쓰기 FAB 노출 — 전체·자유만(공지는 관리자 웹 전용).
  bool get canWrite => this == BoardFilter.all || this == BoardFilter.free;

  /// 사용자 작성 타입 — 항상 free(카테고리 선택 없음).
  BoardType get composeType => BoardType.free;
}
