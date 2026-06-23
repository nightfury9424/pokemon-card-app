import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 게시판 root-navigator 무회귀 잠금 (회귀 방지망, 제품 코드 변경 없음).
///
/// 검증 대상: 게시판 목록·상세는 ShellRoute(하단 탭바·중앙 스캔 FAB 보유) "위"인 root navigator 에
/// push 되어야 하며, 그동안 셸 크롬(하단 탭바·FAB)이 보이지 않고, 복귀하면 다시 보여야 한다.
/// + 셸 child(홈/MY)의 기존 상태가 보존되어야 한다.
///
/// ★실제 제품 구조 반영 / 한계 명시:
/// - app_router: rootNavigatorKey ↔ ShellRoute(_shellNavigatorKey, builder: MainShell). 본 테스트는
///   동일한 "ShellRoute 가 크롬을 감싸고 child 만 교체" 구조를 쓰되, 실제 MainShell 은 직접 쓰지 않는다.
///   이유: MainShell 의 _BottomNav.initState 가 ApiClient.get('/api/chat/rooms') 로 실네트워크 요청을
///   띄워(Dio 30s 타임아웃 타이머) 위젯테스트에서 pending timer 를 만들고, GoRouterState/TokenStorage 에도
///   의존하기 때문. → 경량 셸 프레임(_ShellFrame)으로 대체하되 게시판 진입은 제품과 "동일한"
///   Navigator.of(context, rootNavigator: true).push(...) 패턴(profile_screen:281 / home_notice_banner:58)을 사용.
/// - BoardScreen / BoardDetailScreen 은 실제 제품 위젯(fake repository 주입, board_my_responsive_test 패턴).
/// - 목록→상세(board_screen.dart:278)는 Navigator.of(context).push — BoardScreen 이 root 에 있으므로 root 상속.
///   본 테스트는 실제 BoardScreen 컨텍스트에서 Navigator.of(ctx).push 로 BoardDetailScreen 을 올려 그 상속을
///   그대로 재현한다(실제 PostRow 는 기본=네트워크 repository 로 상세를 생성하므로, 그 탭을 순수 위젯테스트로
///   구동하려면 HTTP 모킹이 필요 → repository 만 fake 로 바꾸고 push 경로는 동일하게 검증).

const _bottomBarKey = Key('shellBottomBar');
const _fabKey = Key('shellFab');
const _entryKey = Key('boardEntry');
const _bumpKey = Key('homeBump');

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

class _FakeRepo extends BoardRepository {
  const _FakeRepo();
  @override
  Future<BoardListResult> fetchList(
      {String? section, String? type, int page = 0, int size = 20}) async {
    return BoardListResult(
        posts: [_post()], page: 0, size: size, totalPages: 1, totalElements: 1);
  }

  @override
  Future<BoardPost?> fetchDetail(String id) async => _post(detail: true);
}

BoardPost _post({bool detail = false}) => BoardPost(
      id: 'rt1',
      type: BoardType.free,
      title: '회귀 테스트 글',
      body: detail ? '상세 본문 회귀' : '목록 미리보기',
      author: '유저',
      createdAt: DateTime(2026, 6, 24, 10),
      listCommentCount: detail ? null : 0,
    );

/// MainShell 과 동일하게 "셸이 크롬(하단탭·FAB)을 감싸고 child 를 교체"하는 경량 프레임.
class _ShellFrame extends StatelessWidget {
  final Widget child;
  const _ShellFrame({required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: child,
        floatingActionButton: const SizedBox(key: _fabKey, width: 56, height: 56),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: const SizedBox(key: _bottomBarKey, height: 64),
      );
}

/// 셸 child(홈/MY 대표). 상태 보존 검증용 카운터 보유.
class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int counter = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('카운터 $counter'),
              ElevatedButton(
                  key: _bumpKey,
                  onPressed: () => setState(() => counter++),
                  child: const Text('증가')),
              ElevatedButton(
                key: _entryKey,
                // 제품과 동일 패턴: root navigator 위로 BoardScreen push.
                onPressed: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                        builder: (_) => const BoardScreen(repository: _FakeRepo()))),
                child: const Text('게시판으로'),
              ),
            ],
          ),
        ),
      );
}

GoRouter _router() => GoRouter(
      navigatorKey: _rootKey,
      initialLocation: '/home',
      routes: [
        ShellRoute(
          navigatorKey: _shellKey,
          builder: (c, s, child) => _ShellFrame(child: child),
          routes: [GoRoute(path: '/home', builder: (c, s) => const _Home())],
        ),
      ],
    );

void main() {
  testWidgets('홈 → 게시판 목록 → 상세 → 뒤로 → 홈: 셸 크롬 가림/복귀 + 홈 상태 보존',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pumpAndSettle();

    // 0. 홈 상태 변경(보존 검증용) — 카운터 2회 증가
    await tester.tap(find.byKey(_bumpKey));
    await tester.tap(find.byKey(_bumpKey));
    await tester.pumpAndSettle();
    expect(find.text('카운터 2'), findsOneWidget);

    // 1. 홈: 하단 탭바·스캔 FAB 보임
    expect(find.byKey(_bottomBarKey), findsOneWidget);
    expect(find.byKey(_fabKey), findsOneWidget);

    // 2. 게시판 목록 진입(root push) → 셸 크롬 미노출 + 실제 BoardScreen 목록 렌더
    await tester.tap(find.byKey(_entryKey));
    await tester.pumpAndSettle();
    expect(find.text('게시판'), findsOneWidget); // BoardScreen AppBar 제목
    expect(find.text('회귀 테스트 글'), findsOneWidget); // 실제 목록 항목(PostRow)
    expect(find.byKey(_bottomBarKey), findsNothing); // 하단 탭바 가림
    expect(find.byKey(_fabKey), findsNothing); // 스캔 FAB 가림

    // 3. 목록→상세와 동일하게 Navigator.of(ctx).push (BoardScreen 이 root → root 상속) → 크롬 미노출
    final ctx = tester.element(find.text('회귀 테스트 글'));
    Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) =>
            const BoardDetailScreen(postId: 'rt1', repository: _FakeRepo())));
    await tester.pumpAndSettle();
    expect(find.text('상세 본문 회귀'), findsOneWidget); // 실제 BoardDetailScreen 본문
    expect(find.byKey(_bottomBarKey), findsNothing);
    expect(find.byKey(_fabKey), findsNothing);

    // 4. 상세 뒤로 → 목록 (크롬 여전히 미노출)
    _rootKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('회귀 테스트 글'), findsOneWidget);
    expect(find.byKey(_bottomBarKey), findsNothing);

    // 5. 목록 뒤로 → 홈 (크롬 재노출 + 홈 상태 보존)
    _rootKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(_bottomBarKey), findsOneWidget);
    expect(find.byKey(_fabKey), findsOneWidget);
    expect(find.text('카운터 2'), findsOneWidget); // 셸 child 상태 유지(offstage maintainState)
    expect(tester.takeException(), isNull);
  });
}
