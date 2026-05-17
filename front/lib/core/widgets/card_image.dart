import 'package:flutter/material.dart';
import '../constants/api_constants.dart';

const _cardBackUrl = 'https://images.scrydex.com/pokemon/card-back/medium';

/// 로컬 이미지 URL 반환 (없으면 null)
String? _localUrl(String? cardId, String lang) {
  if (cardId == null || cardId.isEmpty) return null;
  return '${ApiConstants.baseUrl}/images/cards/${cardId}_$lang.png';
}

/// scrydex CDN URL 반환
String? _cdnUrl(String? ref) {
  if (ref == null || ref.isEmpty || ref.startsWith('NO_')) return null;
  return 'https://images.scrydex.com/pokemon/$ref/medium';
}

/// JP → EN 순으로 로컬 우선, fallback CDN
String? resolveCardImageUrl(Map<String, dynamic>? card) {
  final cardId = card?['cardId'] as String?;
  final jpRef  = card?['jpScrydexRef'] as String?;
  final enRef  = card?['enScrydexRef'] as String?;

  if (jpRef != null) {
    // NO_JP: scrydex CDN 없음, 로컬만 시도
    if (jpRef.startsWith('NO_')) return _localUrl(cardId, 'jp');
    return _localUrl(cardId, 'jp') ?? _cdnUrl(jpRef);
  }
  if (enRef != null) {
    if (enRef.startsWith('NO_')) return _localUrl(cardId, 'en');
    return _localUrl(cardId, 'en') ?? _cdnUrl(enRef);
  }
  return null;
}

/// scrydex CDN URL (로컬 없을 때 fallback용)
String? resolveCdnImageUrl(Map<String, dynamic>? card) {
  final jpRef = card?['jpScrydexRef'] as String?;
  final enRef = card?['enScrydexRef'] as String?;
  return _cdnUrl(jpRef) ?? _cdnUrl(enRef);
}

/// 카드 이미지 위젯
/// - scrydex/pokemontcg.io URL → 이미지 표시
/// - null 또는 pokemonkorea.co.kr URL → 카드 뒷면 + "이미지 없음" 블러 안내
class CardImage extends StatelessWidget {
  final String? imageUrl;
  final String? _cdnFallbackUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const CardImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    String? cdnFallbackUrl,
    this.fit = BoxFit.cover,
    this.borderRadius,
  }) : _cdnFallbackUrl = cdnFallbackUrl;

  bool get _isUnavailable =>
      imageUrl == null ||
      imageUrl!.isEmpty ||
      imageUrl!.contains('pokemonkorea.co.kr');

  @override
  Widget build(BuildContext context) {
    final Widget img = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: _isUnavailable ? _buildUnavailable() : _buildNetwork(),
    );
    return img;
  }

  Widget _buildNetwork() {
    final isCdnUrl = imageUrl!.contains('scrydex.com');
    return Image.network(
      imageUrl!,
      width: width,
      height: height,
      fit: fit,
      // 캐러셀 자동 회전 시 새 URL 로딩 중 이전 frame 유지 → 깜빡임 방지
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) {
        // 로컬 실패 시 CDN으로 재시도
        final cdn = _cdnFallbackUrl;
        if (!isCdnUrl && cdn != null) {
          return Image.network(
            cdn,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _buildUnavailable(),
          );
        }
        return _buildUnavailable();
      },
    );
  }

  Widget _buildUnavailable() {
    return Stack(
      children: [
        Image.network(
          _cardBackUrl,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildFallbackBox(),
        ),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: borderRadius ?? BorderRadius.zero,
            child: Container(
              color: Colors.black45,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_not_supported_outlined,
                      color: Colors.white54, size: width * 0.28),
                  if (height >= 80) ...[
                    const SizedBox(height: 4),
                    Text(
                      '이미지\n없음',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: width * 0.16,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackBox() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: borderRadius,
      ),
      child: Icon(Icons.catching_pokemon, color: Colors.white24, size: width * 0.4),
    );
  }
}
