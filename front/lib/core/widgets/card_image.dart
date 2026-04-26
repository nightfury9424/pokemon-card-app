import 'package:flutter/material.dart';

const _cardBackUrl = 'https://images.scrydex.com/pokemon/card-back/medium';

/// JP → EN 순서로 scrydex 이미지 URL 반환. 없으면 null.
String? resolveCardImageUrl(Map<String, dynamic>? card) {
  final jpRef = card?['jpScrydexRef'] as String?;
  final enRef = card?['enScrydexRef'] as String?;
  if (jpRef != null && jpRef.isNotEmpty && !jpRef.startsWith('NO_')) {
    return 'https://images.scrydex.com/pokemon/$jpRef/medium';
  }
  if (enRef != null && enRef.isNotEmpty && !enRef.startsWith('NO_')) {
    return 'https://images.scrydex.com/pokemon/$enRef/medium';
  }
  return null;
}

/// 카드 이미지 위젯
/// - scrydex/pokemontcg.io URL → 이미지 표시
/// - null 또는 pokemonkorea.co.kr URL → 카드 뒷면 + "이미지 없음" 블러 안내
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

  @override
  Widget build(BuildContext context) {
    final Widget img = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: _isUnavailable ? _buildUnavailable() : _buildNetwork(),
    );
    return img;
  }

  Widget _buildNetwork() {
    return Image.network(
      imageUrl!,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _buildUnavailable(),
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
