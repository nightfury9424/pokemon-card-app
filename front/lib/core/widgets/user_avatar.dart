import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 사용자 프로필 아바타. profileImageUrl 있으면 NetworkImage,
/// 없거나 로드 실패면 기본 아이콘(파란 원 + 사람 실루엣).
/// MY/온보딩/닉네임 변경 등 모든 사용자 아바타 노출 위치에서 통일 사용.
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const UserAvatar({super.key, this.imageUrl, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    if (hasImage) {
      return ClipOval(
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _defaultIcon(),
        ),
      );
    }
    return _defaultIcon();
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
