import 'package:flutter/material.dart';
import '../storage/token_storage.dart';

/// JWT Authorization header를 자동 부착해서 사용자 업로드 이미지(/api/images/secure/**)
/// 를 로드하는 Image 위젯.
///
/// 일반 Image.network는 headers 직접 못 받으니까 FutureBuilder로 토큰 받고 전달.
/// 로딩 동안 placeholder, 실패 시 errorBuilder.
///
/// 사용처:
///   - 자산 등급 분석 사진 (asset_images/)
///   - 거래 이미지 (trade_images/)
///   - 채팅 첨부 이미지
///   - 호가창 row 상세 trade 사진
class AuthImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: TokenStorage.get(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final token = snap.data;
        return Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}
