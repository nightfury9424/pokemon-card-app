import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../network/api_client.dart';

/// 프사/업로드 이미지 세션 메모리 LRU 캐시 (2026-06-05).
/// AuthImage 가 매 렌더마다 JWT 프록시로 재다운로드하던 문제 fix — 동일 URL 은 세션 내 1회만
/// 받고, 채팅목록 스크롤·재진입·여러 방의 같은 유저 프사는 즉시 표시(placeholder flash 없음).
/// 프로세스 생존 동안만 유지. 프사 변경 시 [evict] 로 무효화.
class _AuthImageMemCache {
  _AuthImageMemCache._();
  static final LinkedHashMap<String, Uint8List> _mem = LinkedHashMap();
  static const int _maxEntries = 200;

  static Uint8List? get(String url) {
    final v = _mem.remove(url);
    if (v != null) _mem[url] = v; // LRU 터치
    return v;
  }

  static void put(String url, Uint8List bytes) {
    _mem.remove(url);
    _mem[url] = bytes;
    while (_mem.length > _maxEntries) {
      _mem.remove(_mem.keys.first);
    }
  }

  // ignore: unused_element
  static void evict(String url) => _mem.remove(url);
}

/// 디스크 캐시 (2026-06-11) — 메모리 캐시는 앱 재시작 시 휘발 → 자산 이미지를 매번
/// 프록시(S3 fetch, CloudFront 미캐시)로 재다운로드해 느림. flutter_cache_manager로 영속화.
/// 키 = 프록시 URL(불변). 카드 이미지(_CardCacheManager)와 동일 패턴.
class _AuthImageDiskCache {
  _AuthImageDiskCache._();
  static final CacheManager instance = CacheManager(
    Config(
      'pokefolioAuthImagesV1',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
    ),
  );
}

/// JWT Authorization header를 자동 부착해서 사용자 업로드 이미지(/api/images/secure/**)
/// 를 로드하는 Image 위젯.
///
/// 변경 (2026-05-19): Image.network(headers:) 방식은 iOS release에서 헤더 누락
/// 가능성 + Flutter ImageProvider cache가 headers를 cache key에서 무시.
/// → ApiClient.downloadBytes + Image.memory로 변경. ApiClient interceptor가
/// 100% Authorization header 부착 보장.
///
/// 사용처:
///   - 자산 등급 분석 사진 (asset_images/)
///   - 거래 이미지 (trade_images/)
///   - 채팅 첨부 이미지
///   - 호가창 row 상세 trade 사진
class AuthImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const AuthImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  Uint8List? _cached; // 메모리 캐시 히트 시 즉시 표시(placeholder flash 없음)
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    _cached = _AuthImageMemCache.get(widget.url);
    _future = _cached != null ? null : _load();
  }

  @override
  void didUpdateWidget(AuthImage old) {
    super.didUpdateWidget(old);
    // URL 바뀌면(예: 같은 세션에서 프사 변경) 새로 로드 — stale 이미지 방지.
    if (old.url != widget.url) {
      setState(_init);
    }
  }

  Future<Uint8List?> _load() async {
    try {
      // 1) 디스크 캐시 — 앱 재시작에도 유지(메모리 캐시는 휘발). 적중 시 네트워크 0.
      final cached = await _AuthImageDiskCache.instance.getFileFromCache(widget.url);
      if (cached != null) {
        final bytes = await cached.file.readAsBytes();
        if (bytes.length >= 100) {
          _AuthImageMemCache.put(widget.url, bytes);
          return bytes;
        }
      }
      // 2) 다운로드 → 메모리 + 디스크 캐시.
      final raw = await ApiClient.downloadBytes(widget.url);
      if (raw == null) return null;
      final data = Uint8List.fromList(raw);
      // 정상 이미지(>=100B)만 캐시 — 에러 응답 본문 등 캐싱 방지.
      if (data.length >= 100) {
        _AuthImageMemCache.put(widget.url, data);
        await _AuthImageDiskCache.instance.putFile(
          widget.url, data, maxAge: const Duration(days: 30));
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  Widget _imageOf(Uint8List bytes) => Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: widget.errorBuilder,
      );

  @override
  Widget build(BuildContext context) {
    // 캐시 히트 → 즉시 렌더(다운로드/placeholder 없음).
    if (_cached != null && _cached!.length >= 100) return _imageOf(_cached!);
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // B3-10: 작은 아바타에서 스피너가 "깨진 이미지"처럼 보이던 문제 → 중립 placeholder.
          return Container(
            width: widget.width,
            height: widget.height,
            color: const Color(0xFF1B2230),
          );
        }
        final bytes = snap.data;
        // B3-10: null/빈 값뿐 아니라 비정상 작은 바이트(에러 응답 본문 등)도 에러 처리.
        if (bytes == null || bytes.length < 100) {
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(ctx, snap.error ?? 'no bytes', null);
          }
          return SizedBox(width: widget.width, height: widget.height);
        }
        return _imageOf(bytes);
      },
    );
  }
}
