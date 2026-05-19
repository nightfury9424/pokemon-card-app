import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'models/hoga_board_model.dart';

typedef HogaStatusChanged = void Function(HogaStatus status, HogaGrade? grade);

/// 2단 chip — RAW / PSA / BRG, PSA·BRG 선택 시 [10] [9] sub-row 등장.
///
/// 코인 호가창 스타일 — compact. CGC/BGS 미지원, PSA 9 미만 1차 제외.
class HogaStatusChipBar extends StatelessWidget {
  final HogaStatus selectedStatus;
  final HogaGrade? selectedGrade;
  final HogaStatusChanged onChanged;

  const HogaStatusChipBar({
    super.key,
    required this.selectedStatus,
    required this.selectedGrade,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final needsGrade = selectedStatus.requiresGrade;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: HogaStatus.values.map((s) {
            final isSel = s == selectedStatus;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _Chip(
                label: s.label,
                isSelected: isSel,
                onTap: () {
                  if (s == selectedStatus) return;
                  final defaultGrade =
                      s.requiresGrade ? (selectedGrade ?? HogaGrade.ten) : null;
                  onChanged(s, defaultGrade);
                },
              ),
            );
          }).toList(),
        ),
        if (needsGrade) ...[
          const SizedBox(height: 4),
          Row(
            children: HogaGrade.values.map((g) {
              final isSel = g == selectedGrade;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _Chip(
                  label: g.label,
                  isSelected: isSel,
                  small: true,
                  onTap: () {
                    if (g == selectedGrade) return;
                    onChanged(selectedStatus, g);
                  },
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool small;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    // Polish (2026-05-19):
    // - height 고정 (28/32) → touch target 안정
    // - pill radius (h/2) → 토스 스타일
    // - border 제거 + selected는 채워진 blue
    // - font w600 + letterSpacing -0.2 (한글 가독)
    final h = small ? 28.0 : 32.0;
    final fs = small ? 12.0 : 13.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        height: h,
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.blue : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(h / 2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: fs,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
