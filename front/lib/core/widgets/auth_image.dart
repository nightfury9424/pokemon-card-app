import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../network/api_client.dart';

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
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List?> _load() async {
    debugPrint('[AuthImage] download start url=${widget.url}');
    try {
      final bytes = await ApiClient.downloadBytes(widget.url);
      debugPrint('[AuthImage] download done bytes=${bytes?.length} url=${widget.url}');
      return bytes != null ? Uint8List.fromList(bytes) : null;
    } catch (e) {
      debugPrint('[AuthImage] download error url=${widget.url} err=$e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
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
        // B3-10: null/빈 값뿐 아니라 비정상 작은 바이트(에러 응답 본문 등)도 에러 처리 →
        // Image.memory 가 깨진 글리프를 렌더하지 않고 errorBuilder(기본 아바타)로 폴백.
        if (bytes == null || bytes.length < 100) {
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(ctx, snap.error ?? 'no bytes', null);
          }
          return SizedBox(width: widget.width, height: widget.height);
        }
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }
}
