import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';
import '../theme/app_colors.dart';

/// 앱 업데이트 게이트.
///
/// **① AUTO 강제(기본)** — 앱이 App Store(`itunes.apple.com/lookup`)에서 현재 최신
/// 마케팅버전을 조회해 **설치버전보다 높으면 강제 업데이트**(닫기 불가). 수동설정 0 —
/// 새 버전 출시만 하면 구버전 사용자에게 자동 적용. 강제 대상이 실제 스토어에 존재하므로
/// "전원 잠김(brick)" 구조상 불가. 심사 안전(심사 빌드는 항상 스토어 최신보다 새 버전 → 미발동).
///
/// **② 수동 override(선택)** — S3 `app-config/version.json`(점검과 동일 origin):
/// ```json
/// { "autoForceUpdate": true, "minBuild": 0, "latestBuild": 0, "iosStoreUrl": "...", "message": "" }
/// ```
/// - `autoForceUpdate:false` = ★킬스위치(재빌드 없이 AUTO 강제 OFF).
/// - `minBuild` 미만 빌드 → HARD, `latestBuild` 미만 → SOFT(닫기 가능). 0/0 = 수동 게이트 없음.
/// - 모든 fetch 실패 = fail-open(게이트 없음, 절대 잠그지 않음).
class VersionConfig {
  final int minBuild;
  final int latestBuild;
  final String? storeUrl;
  final String message;
  final bool autoForceUpdate;
  const VersionConfig({
    this.minBuild = 0,
    this.latestBuild = 0,
    this.storeUrl,
    this.message = '',
    this.autoForceUpdate = true,
  });
}

class VersionService {
  VersionService._();

  /// version.json 에 iosStoreUrl 누락 시 폴백 (App ID 6772926395).
  static const _defaultStoreUrl = 'https://apps.apple.com/app/id6772926395';

  /// 이미지 CDN과 동일 origin의 정적 경로 (S3 키: app-config/version.json).
  static String? get _url {
    final base = ApiConstants.cardCdnBase;
    if (base.isEmpty) return null;
    try {
      return Uri.parse(base)
          .replace(path: '/app-config/version.json', query: null)
          .toString();
    } catch (_) {
      return null;
    }
  }

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  /// 실패 시 null → fail-open(절대 사용자 잠그지 않음).
  static Future<VersionConfig?> fetch() async {
    final url = _url;
    if (url == null) return null;
    try {
      final r = await _dio.get(
        url,
        // cache-bust(30s 단위) — 짧은 TTL 보완.
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch ~/ 30000},
        options: Options(responseType: ResponseType.plain),
      );
      final m = jsonDecode(r.data as String) as Map<String, dynamic>;
      int asInt(Object? v) =>
          v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
      final store = (m['iosStoreUrl'] as String?)?.trim();
      return VersionConfig(
        minBuild: asInt(m['minBuild']),
        latestBuild: asInt(m['latestBuild']),
        storeUrl: (store != null && store.isNotEmpty) ? store : null,
        message: (m['message'] as String?)?.trim() ?? '',
        // 명시적 false 만 AUTO 강제 OFF(킬스위치). 없으면/실패면 기본 ON.
        autoForceUpdate: m['autoForceUpdate'] == false ? false : true,
      );
    } catch (_) {
      return null; // ★fail-open.
    }
  }

  static const _bundleId = 'com.fury.pokemoncardapp';

  /// App Store 최신 마케팅버전 조회(itunes lookup). 실패 시 (null,null) → fail-open.
  static Future<({String? version, String? url})> fetchStore() async {
    try {
      final r = await _dio.get(
        'https://itunes.apple.com/lookup',
        queryParameters: {
          'bundleId': _bundleId,
          'country': 'kr',
          't': DateTime.now().millisecondsSinceEpoch ~/ 60000, // 60s 캐시버스트
        },
        options: Options(responseType: ResponseType.plain),
      );
      final m = jsonDecode(r.data as String) as Map<String, dynamic>;
      final results = m['results'] as List?;
      if (results == null || results.isEmpty) return (version: null, url: null);
      final first = results.first as Map<String, dynamic>;
      final v = (first['version'] as String?)?.trim();
      final u = (first['trackViewUrl'] as String?)?.trim();
      return (version: (v != null && v.isNotEmpty) ? v : null, url: u);
    } catch (_) {
      return (version: null, url: null);
    }
  }

  /// semver-ish 비교: a<b → -1, a==b → 0, a>b → 1. 파싱 실패 컴포넌트는 0 취급.
  static int compareVersions(String a, String b) {
    List<int> parse(String v) =>
        v.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    final pa = parse(a), pb = parse(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }

  /// 업데이트 버튼 URL: lookup trackViewUrl > version.json iosStoreUrl > 기본.
  static String bestStoreUrl(String? lookupUrl, VersionConfig? c) {
    if (lookupUrl != null && lookupUrl.isNotEmpty) return lookupUrl;
    if (c?.storeUrl != null && c!.storeUrl!.isNotEmpty) return c.storeUrl!;
    return _defaultStoreUrl;
  }
}

enum _UpdateMode { none, soft, hard }

/// 앱 전역 업데이트 게이트 — child 위에 강제/권장 overlay.
/// 점검 게이트 안쪽에 중첩(`MaintenanceGate(child: VersionGate(child: ...))`)해
/// 우선순위 = 점검 > HARD > SOFT.
class VersionGate extends StatefulWidget {
  final Widget child;
  const VersionGate({super.key, required this.child});

  @override
  State<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<VersionGate> with WidgetsBindingObserver {
  int? _currentBuild;
  String? _currentVersion; // CFBundleShortVersionString (마케팅, 예 "1.0.3")
  String? _storeVersion; // App Store 최신 마케팅버전
  String? _storeUrl; // App Store 페이지 URL(lookup trackViewUrl)
  bool _autoForceEnabled = true; // version.json autoForceUpdate (기본 ON)
  VersionConfig? _config;
  bool _softDismissed = false;
  Timer? _poll;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBuild();
    // 버전은 자주 안 바뀌므로 가볍게(10분) — 시작/resume 이 주 트리거.
    _poll = Timer.periodic(const Duration(minutes: 10), (_) => _check());
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

  Future<void> _initBuild() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentBuild = int.tryParse(info.buildNumber); // CFBundleVersion
      _currentVersion = info.version; // CFBundleShortVersionString
    } catch (_) {
      _currentBuild = null; // 못 읽으면 게이트 없음(fail-open).
      _currentVersion = null;
    }
    await _check();
  }

  Future<void> _check() async {
    final seq = ++_seq; // 늦은 응답이 최신 상태 덮지 않게.
    // version.json(킬스위치/수동 override) + App Store lookup(자동 강제). 둘 다 fail-open.
    // config 가 null(파일 없음/실패)이어도 store 조회는 진행 — AUTO 강제는 기본 ON.
    // 병렬 시작 후 await (worst-case 5s+5s → 5s).
    final fConfig = VersionService.fetch();
    final fStore = VersionService.fetchStore();
    final c = await fConfig;
    final store = await fStore;
    if (!mounted || seq != _seq) return;
    bool dismissed = false;
    if (c != null && c.latestBuild > 0) {
      try {
        final prefs = await SharedPreferences.getInstance();
        // latestBuild 별 키 — 새 버전 나오면 SOFT 다시 1회 노출.
        dismissed =
            prefs.getBool('soft_update_dismissed_${c.latestBuild}') ?? false;
      } catch (_) {}
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _config = c;
      _autoForceEnabled = c?.autoForceUpdate ?? true; // 명시적 false 만 OFF.
      _storeVersion = store.version;
      _storeUrl = store.url;
      _softDismissed = dismissed;
    });
  }

  /// 빌드번호(YYYYMMDDHHMM)를 int 로 인코딩.
  static int _stampOf(DateTime t) =>
      t.year * 100000000 +
      t.month * 1000000 +
      t.day * 10000 +
      t.hour * 100 +
      t.minute;

  /// 안전 상한 = 현재(UTC)+1일. 빌드번호는 빌드 시각이라 항상 과거 → 이 상한 초과 config 는
  /// "아직 존재하지 않는 미래 빌드" 기준이므로 오설정(전원 잠김 사고). UTC+1일 마진으로 KST/시차 흡수.
  int get _ceilingStamp =>
      _stampOf(DateTime.now().toUtc().add(const Duration(days: 1)));

  _UpdateMode get _mode {
    final b = _currentBuild;
    if (b == null) return _UpdateMode.none;
    // ① AUTO 강제 — App Store 최신 마케팅버전 > 설치버전 (kill-switch ON일 때만).
    //   조회 실패(_storeVersion null)면 skip = fail-open. 강제 대상이 스토어에 실재 → brick 불가.
    final cur = _currentVersion;
    final store = _storeVersion;
    if (_autoForceEnabled &&
        cur != null &&
        cur.isNotEmpty &&
        store != null &&
        store.isNotEmpty &&
        VersionService.compareVersions(cur, store) < 0) {
      return _UpdateMode.hard;
    }
    // ② 수동 override — version.json minBuild/latestBuild. 미래가드를 항목별 독립 적용
    //   (Codex: latestBuild 오설정이 valid minBuild HARD 를 무력화하지 않게).
    final c = _config;
    if (c != null) {
      final ceiling = _ceilingStamp;
      final minOk = c.minBuild > 0 && c.minBuild <= ceiling; // 미래/0 아닌 유효 minBuild
      final latestOk = c.latestBuild > 0 && c.latestBuild <= ceiling;
      // 수동 minBuild HARD — self-lock: latestBuild 유효 && minBuild>latestBuild 면 오설정 → skip.
      if (minOk && b < c.minBuild) {
        final selfLock = latestOk && c.minBuild > c.latestBuild;
        if (!selfLock) return _UpdateMode.hard;
      }
      if (latestOk && b < c.latestBuild) return _UpdateMode.soft;
    }
    return _UpdateMode.none;
  }

  Future<void> _launchStore() async {
    final url = VersionService.bestStoreUrl(_storeUrl, _config);
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _dismissSoft() async {
    final c = _config;
    if (c != null && c.latestBuild > 0) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('soft_update_dismissed_${c.latestBuild}', true);
      } catch (_) {}
    }
    if (mounted) setState(() => _softDismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    return Stack(
      children: [
        widget.child,
        if (mode == _UpdateMode.hard)
          Positioned.fill(
            child: _ForceUpdateOverlay(
              message: _config?.message ?? '',
              onUpdate: _launchStore,
            ),
          )
        else if (mode == _UpdateMode.soft && !_softDismissed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SoftUpdateBanner(
              message: _config?.message ?? '',
              onUpdate: _launchStore,
              onLater: _dismissSoft,
            ),
          ),
      ],
    );
  }
}

/// 강제 업데이트 — 닫기 불가 전체 화면. 뒤로가기/스와이프 차단(PopScope).
class _ForceUpdateOverlay extends StatelessWidget {
  final String message;
  final Future<void> Function() onUpdate;
  const _ForceUpdateOverlay({required this.message, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: AppColors.bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset('assets/app_icon/logo.png',
                      width: 88, height: 88),
                ),
                const SizedBox(height: 20),
                const Text('업데이트가 필요해요',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  message.isNotEmpty
                      ? message
                      : '원활한 이용을 위해 최신 버전으로 업데이트해 주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: onUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    child: const Text('업데이트'),
                  ),
                ),
                const SizedBox(height: 14),
                // P1-C: launchUrl 실패(스토어 못 열림)해도 막다른 길 안 되게 폴백 안내.
                const Text(
                  '버튼이 열리지 않으면 App Store에서 “포켓폴리오”를 검색해 업데이트해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 권장 업데이트 — 하단 배너. '나중에'(이 latestBuild 다시 안 뜸) / '업데이트'.
class _SoftUpdateBanner extends StatelessWidget {
  final String message;
  final Future<void> Function() onUpdate;
  final Future<void> Function() onLater;
  const _SoftUpdateBanner({
    required this.message,
    required this.onUpdate,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/app_icon/logo.png',
                  width: 34, height: 34),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('새 버전이 나왔어요',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    message.isNotEmpty ? message : '최신 기능을 받아보세요.',
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onLater,
              child: const Text('나중에',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
            ElevatedButton(
              onPressed: onUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              child: const Text('업데이트'),
            ),
          ],
        ),
      ),
    );
  }
}
