import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../constants/api_constants.dart';

const _cardBackUrl = 'https://images.scrydex.com/pokemon/card-back/medium';

/// 카드 마스터 이미지 전용 cacheManager.
/// S3 cards/v1 prefix가 immutable이라 stalePeriod 1년 + 디스크 객체 상한 2500개.
/// AuthImage(JWT)는 별도 — 사용자 업로드 이미지는 mutate 가능성 있어 캐시 정책 다름.
class _CardCacheManager {
  static const _key = 'pokefolioCardImagesV1';
  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 2500,
    ),
  );
}

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

  if (cardId != null && cardId.isNotEmpty) {
    return '${ApiConstants.cardCdnBase}/special/$cardId.png';
  }
  return null;
}

/// 카드 이미지 위젯
/// - S3 cards/v1 URL → CachedNetworkImage(디스크 캐시) + size-bucket 다운샘플
/// - null 또는 pokemonkorea.co.kr URL → 카드 뒷면 + "이미지 없음" 블러 안내
///
/// 캐시 정책 (Codex 권장):
///   cacheManager  = singleton (_CardCacheManager)
///   stalePeriod   = 365 days  (S3 immutable 활용)
///   maxNrOfCacheObjects = 2500
///   fadeInDuration = 80ms     (Hero/스크롤 깜빡임 방지)
///   useOldImageOnUrlChange = true (gaplessPlayback 대체)
///
/// placeholder = 어두운 surface + 약한 gradient/border (검정 빈 영역 인지 방지)
class CardImage extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const CardImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  bool get _isUnavailable =>
      imageUrl == null ||
      imageUrl!.isEmpty ||
      imageUrl!.contains('pokemonkorea.co.kr');

  /// size-bucket 다운샘플 — 동적 width*DPR 난사 시 변형 폭발 + cache key 충돌 회피.
  /// 작은 grid는 디코딩/메모리도 절감, 같은 카드가 grid↔detail 이동해도 가장 큰 캐시가 재사용됨.
  int? _bucketWidth() {
    if (width <= 0) return null;          // unbounded — Hero/fullscreen 원본
    if (width <= 96) return 384;          // grid 썸네일 (44x62, 56x78, 88x123, 90x126)
    if (width <= 200) return 600;         // mid (호가 row, 캐러셀 큰 카드 등)
    if (width <= 400) return 800;         // detail 카드
    return null;                          // fullscreen / Hero — 원본
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: _isUnavailable ? _buildUnavailable() : _buildNetwork(),
    );
  }

  Widget _buildNetwork() {
    final bw = _bucketWidth();
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      cacheManager: _CardCacheManager.instance,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 80),
      useOldImageOnUrlChange: true,
      memCacheWidth: bw,
      maxWidthDiskCache: bw,
      placeholder: (_, _) => _buildSkeleton(),
      errorWidget: (_, _, _) => _buildUnavailable(),
    );
  }

  /// 로딩 중 카드 shape skeleton — 검정 빈 영역 대신 카드 비율 + 어두운 gradient.
  /// 사용자가 "로딩 중"으로 인지 가능 + spinner 남발 X (UI 노이즈 방지).
  Widget _buildSkeleton() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2937), Color(0xFF111827)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
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
