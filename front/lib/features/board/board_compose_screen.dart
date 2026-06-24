import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/auth_image.dart';
import 'data/board_repository.dart';
import 'models/board_post.dart';
import 'models/board_filter.dart';

/// 게시판 글 작성·수정 — root navigator 전체화면(하단 탭바·스캔 FAB 미노출).
/// editing == null → 작성(카테고리 선택), non-null → 본인 글 수정(타입 고정, 제목·본문·이미지).
/// 결과: 작성 성공 = pop(생성된 postId) / 수정 성공 = pop(true) / 취소 = pop(null).
class BoardComposeScreen extends StatefulWidget {
  final BoardRepository repository;
  final BoardPost? editing;

  /// 작성 시 사전 선택 카테고리(자유/거래후기/사기주의, 전체 탭=자유).
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

enum _UploadState { uploading, done, failed }

/// JPEG 변환 결과 — file(원본 또는 변환 임시파일), isTemp(변환 임시파일이면 정리 대상).
class _Prepared {
  final File file;
  final bool isTemp;
  _Prepared(this.file, this.isTemp);
}

/// 미리보기 1장 — 신규 pick(file→업로드→uploadId) 또는 수정모드 기존 이미지(existingImageId+url).
class _PhotoItem {
  final String key;
  final File? file; // 신규 pick 로컬 파일(썸네일) — 기존이면 null
  final String? existingImageId; // 수정모드 기존 이미지
  final String? existingUrl; // 수정모드 기존 이미지 proxy URL
  final bool isTemp; // image 패키지로 JPEG 변환된 임시파일이면 true → 정리 대상
  String? uploadId; // 업로드 완료 시 세팅(신규)
  _UploadState state;

  _PhotoItem.pick(this.file, {this.isTemp = false})
      : key = UniqueKey().toString(),
        existingImageId = null,
        existingUrl = null,
        uploadId = null,
        state = _UploadState.uploading;

  _PhotoItem.existing(this.existingImageId, this.existingUrl)
      : key = UniqueKey().toString(),
        file = null,
        isTemp = false,
        uploadId = null,
        state = _UploadState.done;

  bool get isExisting => existingImageId != null;
}

/// 잔여 슬롯 계산(테스트 가능) — 현재 current 장 + 선택 picked 장 → 실제 받을 수(최대 max).
int boardPhotoIntakeCount(int current, int picked, {int max = 5}) {
  final remaining = max - current;
  if (remaining <= 0) return 0;
  return picked < remaining ? picked : remaining;
}

class _BoardComposeScreenState extends State<BoardComposeScreen> {
  static const _titleMax = 200;
  static const _bodyMax = 10000;
  static const _maxPhotos = 5;

  late final TextEditingController _title;
  late final TextEditingController _body;
  late final String _initTitle;
  late final String _initBody;
  late BoardType _selectedType;
  late final BoardType _initialType;
  final List<_PhotoItem> _photos = [];
  late final int _initialImageCount;
  bool _submitting = false;

  bool get _isEdit => widget.editing != null;
  bool get _anyUploading => _photos.any((p) => p.state == _UploadState.uploading);
  bool get _anyFailed => _photos.any((p) => p.state == _UploadState.failed);

  bool get _photosDirty =>
      _photos.length != _initialImageCount || _photos.any((p) => !p.isExisting);
  bool get _dirty =>
      _title.text != _initTitle ||
      _body.text != _initBody ||
      _selectedType != _initialType ||
      _photosDirty;

  /// 제목·본문 유효 + 업로드 중/실패 없음 + 저장 중 아님.
  bool get _canSubmit =>
      _title.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty &&
      !_submitting &&
      !_anyUploading &&
      !_anyFailed;

  @override
  void initState() {
    super.initState();
    _initTitle = widget.editing?.title ?? '';
    _initBody = widget.editing?.body ?? '';
    _selectedType = widget.editing?.type ?? widget.initialType ?? BoardType.free;
    _initialType = _selectedType;
    _title = TextEditingController(text: _initTitle)..addListener(_onChange);
    _body = TextEditingController(text: _initBody)..addListener(_onChange);
    // 수정모드: 기존 이미지를 같은 목록으로 표시(sort 순).
    final existing = widget.editing?.images ?? const [];
    for (final img in existing) {
      _photos.add(_PhotoItem.existing(img.imageId, img.url));
    }
    _initialImageCount = _photos.length;
  }

  void _onChange() {
    if (mounted) setState(() {}); // 등록 버튼 활성/글자 수 갱신
  }

  @override
  void dispose() {
    for (final p in _photos) {
      if (p.isTemp && p.file != null) p.file!.delete().ignore(); // 변환 임시파일 정리
    }
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await AppConfirmDialog.show(
      context,
      title: '작성을 취소할까요?',
      message: '작성 중인 내용이 사라져요.',
      cancelLabel: '계속 작성',
      confirmLabel: '나가기',
    );
    return ok ?? false;
  }

  // ───────── 이미지 ─────────
  /// 다중 선택(잔여 슬롯만큼) → 각자 JPEG 확인/변환 → 독립 업로드.
  Future<void> _pickPhotos() async {
    if (_photos.length >= _maxPhotos || _submitting) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 1080);
    if (picked.isEmpty || !mounted) return;
    final take = boardPhotoIntakeCount(_photos.length, picked.length, max: _maxPhotos);
    if (picked.length > take) {
      AppInfoToast.show(context, '사진은 최대 $_maxPhotos장까지 첨부할 수 있어요.');
    }
    for (final x in picked.take(take)) {
      await _intake(x.path); // 선택 순서 유지(순차 추가), 업로드는 각자 독립
    }
  }

  /// 단일 파일 intake — JPEG/PNG 확인(아니면 실제 JPEG 재인코딩) → _photos 추가 → 독립 업로드.
  Future<void> _intake(String path) async {
    final prepared = await _ensureJpegOrPng(File(path));
    if (prepared == null) {
      if (mounted) {
        AppInfoToast.show(context, '지원하지 않는 이미지예요. JPEG 또는 PNG 사진을 첨부해 주세요.');
      }
      return;
    }
    if (!mounted) {
      if (prepared.isTemp) prepared.file.delete().ignore();
      return;
    }
    final item = _PhotoItem.pick(prepared.file, isTemp: prepared.isTemp);
    setState(() => _photos.add(item));
    unawaited(_upload(item));
  }

  /// JPEG/PNG면 원본 그대로, 아니면 image 패키지로 **실제 JPEG 재인코딩**(임시파일·확장자 변경 아님).
  /// image_picker(quality)가 iOS HEIC→JPEG 네이티브 변환을 이미 수행 → 대개 원본이 JPEG.
  /// image 패키지가 디코드 못하는 포맷(미변환 HEIC 등)은 null → 호출부가 안내.
  Future<_Prepared?> _ensureJpegOrPng(File f) async {
    try {
      final bytes = await f.readAsBytes();
      if (_magicJpegOrPng(bytes)) return _Prepared(f, false);
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final jpg = img.encodeJpg(decoded, quality: 85);
      final dir = await getTemporaryDirectory();
      final tmp = File('${dir.path}/board_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(jpg);
      if (!_magicJpegOrPng(await tmp.readAsBytes())) {
        tmp.delete().ignore();
        return null; // 변환 결과 재검증 실패
      }
      return _Prepared(tmp, true);
    } catch (_) {
      return null;
    }
  }

  static bool _magicJpegOrPng(List<int> b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true; // JPEG
    if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true; // PNG
    }
    return false;
  }

  Future<void> _upload(_PhotoItem item) async {
    try {
      final id = await widget.repository.uploadImage(item.file!.path);
      if (!mounted) return;
      setState(() {
        item.uploadId = id;
        item.state = _UploadState.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => item.state = _UploadState.failed);
      final msg = e is BoardApiException ? e.message : '이미지 업로드에 실패했어요.';
      AppInfoToast.show(context, msg);
    }
  }

  void _retry(_PhotoItem item) {
    if (item.file == null) return;
    setState(() => item.state = _UploadState.uploading);
    _upload(item);
  }

  void _remove(_PhotoItem item) {
    if (item.isTemp && item.file != null) item.file!.delete().ignore(); // 변환 임시파일 정리
    setState(() => _photos.remove(item)); // 신규=고아(cron 정리), 기존=S3 보존(목록에서만 제외)
  }

  // ───────── 제출 ─────────
  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final title = _title.text.trim();
    final body = _body.text.trim();
    try {
      if (_isEdit) {
        final images = _photos
            .map((p) => p.isExisting
                ? {'existingImageId': p.existingImageId!}
                : {'uploadId': p.uploadId!})
            .toList();
        await widget.repository
            .updatePost(widget.editing!.id, title: title, content: body, images: images);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final uploadIds = _photos.map((p) => p.uploadId!).toList();
        final id = await widget.repository.createPost(
          type: _selectedType.name,
          title: title,
          content: body,
          imageUploadIds: uploadIds,
        );
        if (!mounted) return;
        Navigator.of(context).pop(id);
      }
    } on BoardApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false); // ★입력·키보드·포커스 유지
      if (e.statusCode == 401) return; // 401=전역 lifecycle 처리
      AppInfoToast.show(
          context,
          e.code == 'CONTENT_POLICY_VIOLATION'
              ? '부적절한 표현이 포함되어 있어 등록할 수 없습니다.' // 고정 문구
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
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_submitting) return; // 저장 중 이탈 금지
        final navigator = Navigator.of(context);
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              _categoryRow(),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                maxLength: _titleMax,
                textInputAction: TextInputAction.next,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: '제목을 입력하세요',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  counterText: '', // 기본 카운터 숨김
                ),
              ),
              _counter(_title.text.characters.length, _titleMax),
              const SizedBox(height: 6),
              const Divider(height: 1, color: AppColors.dividerSoft),
              const SizedBox(height: 6),
              TextField(
                controller: _body,
                maxLength: _bodyMax,
                maxLines: null,
                minLines: 8,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.5),
                decoration: const InputDecoration(
                  hintText: '내용을 입력하세요',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                  counterText: '',
                ),
              ),
              _counter(_body.text.characters.length, _bodyMax),
              _photoSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _counter(int len, int max) => Align(
        alignment: Alignment.centerRight,
        child: Text('$len/$max',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      );

  Widget _categoryRow() {
    final types = _isEdit ? [_selectedType] : userWritableBoardTypes;
    return Wrap(
      spacing: 8,
      children: types.map((t) {
        final sel = t == _selectedType;
        return GestureDetector(
          onTap: _isEdit || _submitting ? null : () => setState(() => _selectedType = t),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppColors.blueDeep.withValues(alpha: 0.30) : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: sel ? AppColors.blue : AppColors.divider,
                width: sel ? 1.4 : 1,
              ),
            ),
            child: Text(t.label,
                style: TextStyle(
                  color: sel ? AppColors.blueLight : AppColors.textSecondary,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13.5,
                )),
          ),
        );
      }).toList(),
    );
  }

  Widget _photoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.dividerSoft),
        const SizedBox(height: 16),
        Text('사진 첨부 ${_photos.length}/$_maxPhotos',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in _photos) _thumb(p),
              if (_photos.length < _maxPhotos) _addTile(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumb(_PhotoItem p) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 78,
        height: 78,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: p.isExisting
                  ? AuthImage(url: p.existingUrl!, width: 78, height: 78, fit: BoxFit.cover)
                  : Image.file(p.file!, width: 78, height: 78, fit: BoxFit.cover),
            ),
            if (p.state == _UploadState.uploading)
              _overlay(const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))),
            if (p.state == _UploadState.failed)
              _overlay(GestureDetector(
                onTap: () => _retry(p),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: Colors.white, size: 22),
                    Text('재시도', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              )),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _remove(p),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, color: Colors.white, size: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlay(Widget child) => Positioned.fill(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(color: Colors.black.withValues(alpha: 0.45), child: Center(child: child)),
        ),
      );

  Widget _addTile() {
    return GestureDetector(
      onTap: _pickPhotos,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }
}
