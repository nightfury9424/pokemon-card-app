import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'auth_image.dart';

/// 사용자 프로필 아바타. 없거나 실패면 기본 아이콘(파란 원 + 사람 실루엣).
/// B2-10: 업로드 이미지는 proxy URL(/api/images/secure/...)이라 AuthImage(JWT)로 로드,
///         legacy 전체 URL(http)은 Image.network. MY/온보딩/프로필편집/채팅 통일 사용.
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const UserAvatar({super.key, this.imageUrl, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return _defaultIcon();
    final isFullUrl = url.startsWith('http');
    return ClipOval(
      child: isFullUrl
          ? Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _defaultIcon(),
            )
          : AuthImage(
              url: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _defaultIcon(),
            ),
    );
  }

  Widget _defaultIcon() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_rounded,
        color: AppColors.blue,
        size: size * 0.5,
      ),
    );
  }
}
