import 'package:flutter/material.dart';
import '../../../core/widgets/app_segmented_toggle.dart';
import 'models/hoga_board_model.dart';

typedef HogaStatusChanged = void Function(HogaStatus status, HogaGrade? grade);

/// 2단 토글 — RAW / PSA / BRG, PSA·BRG 선택 시 [10] [9] sub-row 등장.
/// 앱 공통 AppSegmentedToggle 톤으로 통일.
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
    final statuses = HogaStatus.values;
    final grades = HogaGrade.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSegmentedToggle(
          labels: statuses.map((s) => s.label).toList(),
          selectedIndex: statuses.indexOf(selectedStatus),
          onChanged: (i) {
            final s = statuses[i];
            if (s == selectedStatus) return;
            final defaultGrade =
                s.requiresGrade ? (selectedGrade ?? HogaGrade.ten) : null;
            onChanged(s, defaultGrade);
          },
        ),
        if (needsGrade) ...[
          const SizedBox(height: 6),
          AppSegmentedToggle(
            labels: grades.map((g) => g.label).toList(),
            selectedIndex:
                selectedGrade == null ? -1 : grades.indexOf(selectedGrade!),
            onChanged: (i) {
              final g = grades[i];
              if (g == selectedGrade) return;
              onChanged(selectedStatus, g);
            },
          ),
        ],
      ],
    );
  }
}
