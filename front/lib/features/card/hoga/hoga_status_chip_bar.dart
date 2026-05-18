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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(
          horizontal: small ? 9 : 11,
          vertical: small ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.blueDeep : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.blue : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: small ? 11 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
