import 'package:flutter/material.dart';
import '../constants/api_constants.dart';

const _cardBackUrl = 'https://images.scrydex.com/pokemon/card-back/medium';

bool _hasValidRef(String? ref) =>
    ref != null && ref.isNotEmpty && !ref.startsWith('NO_');

/// dev 환경 한정. prod 빌드에서는 항상 null.
String? _localUrl(String? cardId, String lang) {
  if (!ApiConstants.useLocalCardImages) return null;
  if (cardId == null || cardId.isEmpty) return null;
  return '${ApiConstants.baseUrl}/images/cards/${cardId}_$lang.png';
}

/// S3 cards/v1/{lang}/{cardId}.png — prod 표준.
String? _s3Url(String? cardId, String lang) {
  if (cardId == null || cardId.isEmpty) return null;
  return '${ApiConstants.cardCdnBase}/$lang/$cardId.png';
}

/// scrydex CDN URL — JP/EN 미러링 안정화 전까지 CardImage.cdnFallbackUrl로만 사용.
/// 미러링 완료 후 폐기 예정.
String? _cdnUrl(String? ref) {
  if (ref == null || ref.isEmpty || ref.startsWith('NO_')) return null;
  return 'https://images.scrydex.com/pokemon/$ref/medium';
}

/// 카드 마스터 이미지 URL 결정.
///
/// 우선순위:
///   dev (USE_LOCAL_CARD_IMAGES=true):
///     local jp → local en → S3 jp → S3 en → S3 special → null
///   prod:
///     S3 jp → S3 en → S3 special → null
///
/// KO fallback은 정책상 넣지 않음 (한국판 이미지 보류).
String? resolveCardImageUrl(Map<String, dynamic>? card) {
  final cardId = card?['cardId'] as String?;
  final jpRef  = card?['jpScrydexRef'] as String?;
  final enRef  = card?['enScrydexRef'] as String?;

  if (ApiConstants.useLocalCardImages) {
    if (_hasValidRef(jpRef)) {
      final u = _localUrl(cardId, 'jp');
      if (u != null) return u;
    }
    if (_hasValidRef(enRef)) {
      final u = _localUrl(cardId, 'en');
      if (u != null) return u;
    }
  }

  if (_hasValidRef(jpRef)) return _s3Url(cardId, 'jp');
  if (_hasValidRef(enRef)) return _s3Url(cardId, 'en');

  // 둘 다 NO_/null → special. 현재는 메타몽 1장만 S3에 있음.
  if (cardId != null && cardId.isNotEmpty) {
    return '${ApiConstants.cardCdnBase}/special/$cardId.png';
  }
  return null;
}

/// scrydex CDN URL — CardImage.cdnFallbackUrl로 전달해 S3 객체 미존재 시 임시 fallback.
/// JP/EN 미러링 완료 후 호출처 정리 + 폐기 예정.
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
            errorBuilder: (_, _, _) => _buildUnavailable(),
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
          errorBuilder: (_, _, _) => _buildFallbackBox(),
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
