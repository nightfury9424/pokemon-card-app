import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../router/app_router.dart';
import '../theme/app_colors.dart';

/// 포그라운드(앱 켜져 있을 때) FCM 수신 시 화면 상단에 슬라이드 다운으로 뜨는
/// 앱 자체 인앱 배너. OS 시스템 배너 대신 앱 톤에 맞춘 커스텀 UI.
///
/// - BuildContext 없이 서비스(PushNotificationService)에서 호출 → rootNavigatorKey overlay 주입
/// - 사용자 정책: Material SnackBar/MaterialBanner 금지 → OverlayEntry 직접 사용
/// - 큐잉: 동시 다발 수신 시 순차 표시(최대 3개), 같은 내용 중복 제거
/// - 탭 → onTap 라우팅 + 닫힘 / 위로 스와이프 → 닫힘 / 3.8초 후 자동 닫힘
class InAppNotification {
  static final Queue<_BannerData> _queue = Queue<_BannerData>();
  static bool _showing = false;
  static _BannerData? _showingData; // 현재 표시 중인 배너 — dedupe 에 포함.

  static void show({
    required String title,
    required String body,
    VoidCallback? onTap,
    String? imageUrl,
  }) {
    if (title.isEmpty && body.isEmpty) return;
    // 중복 제거 — 큐 + "현재 표시 중" 배너에 동일 title+body 가 있으면 skip.
    // (현재 배너 미포함 시 "사진을 보냈어요" 같은 고정 문구 연속 수신에 배너 2번 뜸)
    bool sameContent(_BannerData? d) =>
        d != null && d.title == title && d.body == body;
    if (sameContent(_showingData) || _queue.any(sameContent)) return;
    _queue.add(_BannerData(
        title: title, body: body, onTap: onTap, imageUrl: imageUrl));
    // 큐 폭주 방지 — 최대 3개 보관(오래된 것부터 폐기).
    while (_queue.length > 3) {
      _queue.removeFirst();
    }
    if (!_showing) _showNext();
  }

  static void _showNext() {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (_queue.isEmpty || overlay == null) {
      _showing = false;
      _showingData = null;
      return;
    }
    _showing = true;
    final data = _queue.removeFirst();
    _showingData = data;
    late OverlayEntry entry;
    bool removed = false;
    void close() {
      if (removed) return;
      removed = true;
      entry.remove();
      _showNext();
    }

    entry = OverlayEntry(
      builder: (_) => _BannerBody(data: data, onClose: close),
    );
    overlay.insert(entry);
  }
}

class _BannerData {
  final String title;
  final String body;
  final VoidCallback? onTap;
  final String? imageUrl; // 카톡식 — 상대 프사 (없으면 이니셜/아이콘 fallback)
  const _BannerData(
      {required this.title, required this.body, this.onTap, this.imageUrl});
}

class _BannerBody extends StatefulWidget {
  final _BannerData data;
  final VoidCallback onClose;
  const _BannerBody({required this.data, required this.onClose});

  @override
  State<_BannerBody> createState() => _BannerBodyState();
}

class _BannerBodyState extends State<_BannerBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
    _c.forward();
    _timer = Timer(const Duration(milliseconds: 3800), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) {
      await _c.reverse();
    }
    widget.onClose();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// 카톡식 아바타 — 상대 프사(둥근 사각형), 없거나 로드 실패 시 이니셜/사람 아이콘.
  Widget _avatar() {
    final url = widget.data.imageUrl;
    final initial =
        widget.data.title.isNotEmpty ? widget.data.title.substring(0, 1) : '';
    final Widget fallback = Container(
      color: AppColors.blue.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: initial.isNotEmpty
          ? Text(initial,
              style: const TextStyle(
                  color: AppColors.blueLight,
                  fontSize: 18,
                  fontWeight: FontWeight.w800))
          : const Icon(Icons.person_rounded,
              color: AppColors.blueLight, size: 22),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: 42,
        height: 42,
        child: (url != null && url.startsWith('http'))
            ? Image.network(url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => fallback,
                loadingBuilder: (c, child, p) => p == null ? child : fallback)
            : fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {
                  widget.data.onTap?.call();
                  _dismiss();
                },
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < 0) _dismiss();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.textPrimary.withValues(alpha: 0.06)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // 아이콘은 상대 프사(http)가 있을 때만 — 거래/시스템 알림의
                      // 첫글자 네모 박스("거" 등) 제거(사용자 요청), 텍스트만 노출.
                      if ((widget.data.imageUrl?.startsWith('http')) ?? false) ...[
                        _avatar(),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.data.title.isNotEmpty)
                              Text(
                                widget.data.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            if (widget.data.title.isNotEmpty &&
                                widget.data.body.isNotEmpty)
                              const SizedBox(height: 2),
                            if (widget.data.body.isNotEmpty)
                              Text(
                                widget.data.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textPrimary
                                      .withValues(alpha: 0.72),
                                  fontSize: 12.5,
                                  height: 1.25,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
