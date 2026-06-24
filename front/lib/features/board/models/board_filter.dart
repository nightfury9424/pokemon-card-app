import 'board_post.dart';

/// 게시판 탭/필터 — ★의미 기반(숫자 인덱스 폐기). 목업 7탭: 전체|공지|이벤트|패치노트|자유|거래후기|사기주의.
/// 진입은 `BoardScreen(initialFilter: BoardFilter.notice)` 처럼 의미로 — 탭 순서가 바뀌어도 깨지지 않음.
/// (기존 `initialTab: 0/1` 은 새 구조에서 0=전체가 되어 홈 공지 화살표가 어긋나므로 제거.)
enum BoardFilter { all, notice, event, patch, free, tradeReview, scamAlert }

extension BoardFilterX on BoardFilter {
  /// 탭 라벨.
  String get label {
    switch (this) {
      case BoardFilter.all:
        return '전체';
      case BoardFilter.notice:
        return '공지';
      case BoardFilter.event:
        return '이벤트';
      case BoardFilter.patch:
        return '패치노트';
      case BoardFilter.free:
        return '자유';
      case BoardFilter.tradeReview:
        return '거래후기';
      case BoardFilter.scamAlert:
        return '사기주의';
    }
  }

  /// 서버 조회 type. 전체는 null(미필터, 백엔드가 qna 제외). 그 외는 해당 type.
  String? get queryType {
    switch (this) {
      case BoardFilter.all:
        return null;
      case BoardFilter.notice:
        return 'notice';
      case BoardFilter.event:
        return 'event';
      case BoardFilter.patch:
        return 'patch';
      case BoardFilter.free:
        return 'free';
      case BoardFilter.tradeReview:
        return 'tradeReview';
      case BoardFilter.scamAlert:
        return 'scamAlert';
    }
  }

  /// 글쓰기 FAB 노출 여부 — 전체(기본 자유) + 자유/거래후기/사기주의. 공식(공지/이벤트/패치)은 미노출.
  bool get canWrite =>
      this == BoardFilter.all ||
      this == BoardFilter.free ||
      this == BoardFilter.tradeReview ||
      this == BoardFilter.scamAlert;

  /// 작성 진입 시 사전 선택할 타입. 전체→자유, 작성탭→해당 타입. 비작성 탭이면 null.
  BoardType? get composeType {
    switch (this) {
      case BoardFilter.all:
      case BoardFilter.free:
        return BoardType.free;
      case BoardFilter.tradeReview:
        return BoardType.tradeReview;
      case BoardFilter.scamAlert:
        return BoardType.scamAlert;
      default:
        return null;
    }
  }
}

/// 글쓰기 카테고리 선택기에 노출하는 사용자 작성 가능 타입(공식·qna 제외). 백엔드 isUserWritableType 와 일치.
const List<BoardType> userWritableBoardTypes = [
  BoardType.free,
  BoardType.tradeReview,
  BoardType.scamAlert,
];
