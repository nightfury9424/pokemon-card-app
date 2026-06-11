import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants/api_constants.dart';
import '../../features/maintenance/maintenance_screen.dart';

/// 점검(maintenance) 설정. 백엔드와 **독립**된 정적 maintenance.json(이미지 CDN/CloudFront).
/// 백엔드 완전 다운(재시작)에도 응답 가능. fetch 실패 = **fail-open**(점검 아님, 정상 진행).
class MaintenanceConfig {
  final bool maintenance;
  final String message;
  const MaintenanceConfig({required this.maintenance, required this.message});
  static const off = MaintenanceConfig(maintenance: false, message: '');
}

class MaintenanceService {
  MaintenanceService._();

  static const _defaultMessage =
      '더 나은 서비스를 위해 점검 중입니다.\n잠시 후 다시 이용해 주세요.';

  /// 이미지 CDN과 동일 CloudFront origin의 정적 경로. (S3 키: app-config/maintenance.json)
  /// 운영 토글 = 이 파일 재업로드 (CloudFront TTL 30~60s + 필요시 invalidation).
  static String? get _url {
    final base = ApiConstants.cardCdnBase; // 예: https://xxx.cloudfront.net/cards/v1
    if (base.isEmpty) return null;
    try {
      return Uri.parse(base)
          .replace(path: '/app-config/maintenance.json', query: null)
          .toString();
    } catch (_) {
      return null;
    }
  }

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  static Future<MaintenanceConfig> fetch() async {
    final url = _url;
    if (url == null) return MaintenanceConfig.off;
    try {
      final r = await _dio.get(
        url,
        // cache-bust(30s 단위) — 짧은 TTL 보완해 토글 빠른 반영.
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch ~/ 30000},
        options: Options(responseType: ResponseType.plain),
      );
      final m = jsonDecode(r.data as String) as Map<String, dynamic>;
      if (m['maintenance'] == true) {
        final msg = (m['message'] as String?)?.trim();
        return MaintenanceConfig(
          maintenance: true,
          message: (msg != null && msg.isNotEmpty) ? msg : _defaultMessage,
        );
      }
      return MaintenanceConfig.off;
    } catch (_) {
      return MaintenanceConfig.off; // ★fail-open — 점검json 못 받으면 정상 진행.
    }
  }
}

/// 앱 전역 점검 게이트 — 시작 + foreground resume + (점검 중일 때) 30s poll 로
/// maintenance.json 확인 후, 점검이면 [MaintenanceScreen]으로 전체 가림.
/// MaterialApp.builder 에서 child 를 감싸 모든 라우트 위에 동작.
class MaintenanceGate extends StatefulWidget {
  final Widget child;
  const MaintenanceGate({super.key, required this.child});

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate>
    with WidgetsBindingObserver {
  MaintenanceConfig _config = MaintenanceConfig.off;
  Timer? _poll;
  int _checkSeq = 0; // 동시성 가드용 시퀀스.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    // 항상 주기 체크(60s) — 정상 사용 중 점검이 켜져도 60s 내 감지(resume/restart 전에도).
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final seq = ++_checkSeq; // ★늦게 끝난 예전 응답이 최신 상태를 덮지 않게.
    final c = await MaintenanceService.fetch();
    if (!mounted || seq != _checkSeq) return;
    if (c.maintenance != _config.maintenance || c.message != _config.message) {
      setState(() => _config = c);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ★child를 항상 mount 유지(Navigator/스크롤/입력/모달/nested-nav state 보존) +
    //   점검 시 전체 overlay. (child 자체를 대체하면 점검 해제 후 화면 state 날아감 — Codex P1.)
    return Stack(
      children: [
        widget.child,
        if (_config.maintenance)
          Positioned.fill(
            child: MaintenanceScreen(message: _config.message, onRetry: _check),
          ),
      ],
    );
  }
}
