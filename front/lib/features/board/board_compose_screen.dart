import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import 'data/board_repository.dart';
import 'models/board_post.dart';

/// 자유게시판 글 작성·수정 — root navigator 전체화면(하단 탭바·스캔 FAB 미노출).
/// editing == null → 작성, non-null → 본인 자유글 수정(제목·본문만, 서버가 권한 재검증).
/// 결과: 작성 성공 = pop(생성된 postId) / 수정 성공 = pop(true) / 취소 = pop(null).
class BoardComposeScreen extends StatefulWidget {
  final BoardRepository repository;
  final BoardPost? editing;

  /// 작성 시 사전 선택 카테고리(자유/거래후기/사기주의). 카테고리 picker UI 는 후속 슬라이스.
  final BoardType? initialType;
  const BoardComposeScreen({
    super.key,
    this.repository = const BoardRepository(),
    this.editing,
    this.initialType,
  });

  @override
  State<BoardComposeScreen> createState() => _BoardComposeScreenState();
}

class _BoardComposeScreenState extends State<BoardComposeScreen> {
  static const _titleMax = 200;
  static const _bodyMax = 10000;

  late final TextEditingController _title;
  late final TextEditingController _body;
  late final String _initTitle;
  late final String _initBody;
  bool _submitting = false;

  bool get _isEdit => widget.editing != null;
  bool get _dirty => _title.text != _initTitle || _body.text != _initBody;
  bool get _canSubmit =>
      _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty && !_submitting;

  @override
  void initState() {
    super.initState();
    _initTitle = widget.editing?.title ?? '';
    _initBody = widget.editing?.body ?? '';
    _title = TextEditingController(text: _initTitle)..addListener(_onChange);
    _body = TextEditingController(text: _initBody)..addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {}); // 등록 버튼 활성/글자 수 갱신
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('작성을 취소할까요?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: const Text('작성 중인 내용이 사라져요.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('계속 작성', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('나가기',
                  style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return; // 연타·빈 입력 가드
    setState(() => _submitting = true);
    final title = _title.text.trim();
    final body = _body.text.trim();
    try {
      if (_isEdit) {
        await widget.repository.updatePost(widget.editing!.id, title: title, content: body);
        if (!mounted) return;
        Navigator.of(context).pop(true); // 수정 성공 (force pop — PopScope 우회)
      } else {
        final id = await widget.repository.createPost(
          type: (widget.initialType ?? BoardType.free).name,
          title: title,
          content: body,
        );
        if (!mounted) return;
        Navigator.of(context).pop(id); // 작성 성공 → postId 반환
      }
    } on BoardApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false); // ★입력·키보드·포커스 유지(unfocus 안 함)
      if (e.statusCode == 401) return; // 401=전역 lifecycle(로그아웃)이 처리
      AppInfoToast.show(
          context,
          e.code == 'CONTENT_POLICY_VIOLATION'
              ? '부적절한 표현이 포함되어 있어 등록할 수 없습니다.' // 고정 문구 — 탐지 단어 미노출
              : e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppInfoToast.show(context, '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 뒤로(시스템·AppBar)는 가로채 폐기 확인. 제출 성공 pop 은 force pop 으로 우회.
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_submitting) return; // ★저장 요청 중엔 이탈·폐기확인 금지(성공 결과 유실 방지). 완료/실패 후 가능.
        final navigator = Navigator.of(context); // async gap 전 캡처(context-after-await 회피)
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: Text(_isEdit ? '글 수정' : '글쓰기',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton(
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? '저장' : '등록',
                        style: TextStyle(
                            color: _canSubmit ? AppColors.blue : AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextField(
                controller: _title,
                maxLength: _titleMax,
                textInputAction: TextInputAction.next,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: '제목',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                ),
              ),
              const Divider(height: 1, color: AppColors.dividerSoft),
              const SizedBox(height: 4),
              TextField(
                controller: _body,
                maxLength: _bodyMax,
                maxLines: null,
                minLines: 8,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline, // 완료키로 자동 등록 안 함(줄바꿈)
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, height: 1.5),
                decoration: const InputDecoration(
                  hintText: '자유롭게 작성해 주세요.',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
