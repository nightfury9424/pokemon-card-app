import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// PokeFolio 톤 segmented toggle.
///
/// 사용:
///   AppSegmentedToggle(
///     labels: ['원본 보기', '후보 강조 보기', '후보 위치 표시'],
///     selectedIndex: _idx,
///     onChanged: (i) => setState(() => _idx = i),
///   )
///
/// 디자인 (2026-06-02 premium 보정):
/// - track = surfaceCard well(너무 검정 X) + divider border + radius 12
/// - selected = AppColors.blue pill + 미세 shadow(살짝 떠 보이게) + 흰 w800
/// - unselected = transparent + textSecondary w600
/// - Material 기본 ToggleButtons / SegmentedButton 사용 X (앱 톤 유지)
class AppSegmentedToggle extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;

  const AppSegmentedToggle({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        // well 을 너무 검정(AppColors.bg)으로 깔면 싸 보임 → surfaceCard 톤.
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
                decoration: BoxDecoration(
                  color: selected ? AppColors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.blue.withValues(alpha: 0.32),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
