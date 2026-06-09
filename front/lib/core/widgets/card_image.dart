import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../constants/api_constants.dart';
import '../theme/app_colors.dart';

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

/// B2-1: 카드 이미지 캐시 워밍 — 캐러셀 렌더 전에 미리 받아 "검정 skeleton flash" 방지.
/// 실패는 무시(네트워크/취소). CardImage와 동일 cacheManager 사용.
Future<void> precacheCardImage(BuildContext context, String? url) async {
  if (url == null || url.isEmpty || url.contains('pokemonkorea.co.kr')) return;
  try {
    await precacheImage(
      CachedNetworkImageProvider(url, cacheManager: _CardCacheManager.instance),
      context,
    );
  } catch (_) {
    // 무시 — 실패해도 CardImage가 placeholder로 처리.
  }
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
    // ★ width: double.infinity (레이아웃이 크기 결정 — 캐러셀/홈 히어로/거래상세/자산 큰 카드)는
    //   여기서 풀해상도 디코드되면(이전: 맨 끝 return null) 체이스 고해상도 PNG 여러 장을 원본으로 동시
    //   디코드 → iOS 메모리 압박 → 디코드 텍스처 purge → "회색 박스". 1024 로 캡해 다운샘플(표시 크기엔 충분).
    if (width.isInfinite) return 1024;
    if (width <= 0) return null;          // 진짜 원본 (fullscreen 뷰어 등 명시적 unbounded)
    if (width <= 96) return 384;          // grid 썸네일 (44x62, 56x78, 88x123, 90x126)
    if (width <= 200) return 600;         // mid (호가 row, 캐러셀 큰 카드 등)
    if (width <= 400) return 800;         // detail 카드
    return null;                          // 그 외 — 원본
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      // ★ 이미지가 페인트되기 전 1프레임 갭(precache miss·재디코드)에도 회색 컴포지터 fill 대신
      //   다크 카드 배경이 보이게 — 로드가 느려도 '회색박스' 없이 깔끔한 다크 placeholder.
      child: ColoredBox(
        color: AppColors.surfaceCard,
        child: _isUnavailable ? _buildUnavailable() : _buildNetwork(),
      ),
    );
  }

  Widget _buildNetwork() {
    // 일시적 네트워크 실패(셀룰러/혼잡)에 "이미지 없음"으로 굳지 않도록 백오프 재시도.
    // S3 파일은 존재하므로 대부분 재시도로 복구됨. 재시도 소진 후에만 unavailable 표시.
    return _RetryingNetworkImage(
      imageUrl: imageUrl!,
      width: width,
      height: height,
      fit: fit,
      bucketWidth: _bucketWidth(),
      skeleton: _buildSkeleton(),
      unavailable: _buildUnavailable(),
    );
  }

  /// 로딩 중 카드 shape skeleton — 검정 빈 영역 대신 카드 비율 + 어두운 gradient.
  /// 사용자가 "로딩 중"으로 인지 가능 + spinner 남발 X (UI 노이즈 방지).
  Widget _buildSkeleton() {
    // B2-1: 검정 빈박스로 인지되지 않게 — 살짝 밝은 카드톤 + 포켓볼 워터마크로 "로딩 중 카드"임을 명시.
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A3346), Color(0xFF1B2230)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Icon(
        Icons.catching_pokemon,
        color: Colors.white.withValues(alpha: 0.10),
        // width=double.infinity(레이아웃이 크기 결정)면 width*계수가 ♾️ → Icon fontSize 무한
        //   → 'fontSize.isFinite' assert(디버그 폭주 / 릴리즈 무음). 무한이면 상수로 클램프.
        size: width.isFinite && width > 0 ? width * 0.32 : 64,
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
                      color: Colors.white54,
                      size: width.isFinite ? width * 0.28 : 56),
                  if (height >= 80) ...[
                    const SizedBox(height: 4),
                    Text(
                      '이미지\n없음',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: width.isFinite ? width * 0.16 : 13,
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
      child: Icon(Icons.catching_pokemon, color: Colors.white24,
          size: width.isFinite ? width * 0.4 : 64),
    );
  }
}

/// CachedNetworkImage 래퍼 — 로드 실패 시 백오프로 자동 재시도.
///
/// 배경: S3 카드 이미지는 거의 전부 존재하지만, 홈 진입 시 이미지가 한꺼번에 몰리면
/// 셀룰러/혼잡으로 일부 GET이 일시 실패한다. CachedNetworkImage는 실패를 재시도하지
/// 않고 errorWidget("이미지 없음")으로 굳어버린다. 여기서 짧은 백오프로 재시도해
/// 일시 실패를 복구하고, 재시도를 소진했을 때만 unavailable 을 보여준다.
class _RetryingNetworkImage extends StatefulWidget {
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final int? bucketWidth;
  final Widget skeleton;
  final Widget unavailable;

  const _RetryingNetworkImage({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.fit,
    required this.bucketWidth,
    required this.skeleton,
    required this.unavailable,
  });

  @override
  State<_RetryingNetworkImage> createState() => _RetryingNetworkImageState();
}

class _RetryingNetworkImageState extends State<_RetryingNetworkImage> {
  // 셀룰러/통화 중 일시 실패로 이미지가 있는데도 "이미지 없음"으로 굳던 문제 → 재시도 2→4.
  // (근본 속도/실패율은 CDN 도입이 해결. 여기선 회복력만 강화.)
  static const _maxRetries = 4;
  int _attempt = 0;

  @override
  void didUpdateWidget(_RetryingNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) _attempt = 0; // URL 바뀌면 재시도 카운트 리셋
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      // attempt 를 key 에 포함 → 실패 후 재시도 시 provider 가 네트워크를 다시 친다.
      key: ValueKey('${widget.imageUrl}#$_attempt'),
      imageUrl: widget.imageUrl,
      cacheManager: _CardCacheManager.instance,
      // ★ double.infinity 를 그대로 넘기면 OctoImage 가 SizedBox(infinity,infinity)로 감싸고
      //   첫 프레임 도착 전 Image/RawImage 가 회색 컴포지터 fill 로 그려짐(캐러셀 회색박스 근본원인).
      //   null 로 넘겨 부모(AspectRatio/Expanded) 제약이 사이즈를 정하게 하면 placeholder(다크 skeleton)가 정상 표시.
      width: widget.width.isFinite ? widget.width : null,
      height: widget.height.isFinite ? widget.height : null,
      fit: widget.fit,
      fadeInDuration: const Duration(milliseconds: 80),
      useOldImageOnUrlChange: true,
      memCacheWidth: widget.bucketWidth,
      maxWidthDiskCache: widget.bucketWidth,
      placeholder: (_, _) => widget.skeleton,
      errorWidget: (_, _, _) {
        if (_attempt < _maxRetries) {
          // 백오프 후 재시도 — 재시도 중에는 "이미지 없음" 대신 skeleton 유지.
          final delayMs = 500 * (1 << _attempt); // 500ms, 1000ms
          Future.delayed(Duration(milliseconds: delayMs), () {
            if (mounted) setState(() => _attempt++);
          });
          return widget.skeleton;
        }
        return widget.unavailable;
      },
    );
  }
}

/// 카드 썸네일 받침대 — 다크 배경(AppColors.bg) 위에 카드가 받침 없이 떠/잘려 붙은 느낌이
/// 나지 않도록 surface 배경 + 약한 border 로 감싼다. 카드 이미지 자체는 [width]×[height] 유지하고
/// 받침대만 [padding] 만큼 바깥으로 약간 커진다(이미지 축소 X). 거래 리스트·관심목록 썸네일용.
class CardThumb extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final double padding;
  final double radius;

  const CardThumb({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.padding = 3,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      child: CardImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        borderRadius:
            BorderRadius.circular((radius - padding).clamp(4.0, radius)),
      ),
    );
  }
}
