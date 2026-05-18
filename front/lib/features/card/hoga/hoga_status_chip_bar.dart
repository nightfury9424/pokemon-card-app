import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'models/hoga_board_model.dart';

typedef HogaStatusChanged = void Function(HogaStatus status);

/// RAW / PSA10 / BRG chip bar. CGC/BGS 미지원.
class HogaStatusChipBar extends StatelessWidget {
  final HogaStatus selected;
  final HogaStatusChanged onChanged;

  const HogaStatusChipBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: HogaStatus.values.map((status) {
        final isSel = status == selected;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => onChanged(status),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSel ? AppColors.blueDeep : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSel ? AppColors.blue : AppColors.divider,
                ),
              ),
              child: Text(
                status.label,
                style: TextStyle(
                  color: isSel ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
