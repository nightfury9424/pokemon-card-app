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
/// 디자인:
/// - 둥근 모서리, 단일 outer container + 내부 segment row
/// - selected = AppColors.blue 배경 + 흰 텍스트
/// - unselected = transparent + textSecondary
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
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                decoration: BoxDecoration(
                  color: selected ? AppColors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
