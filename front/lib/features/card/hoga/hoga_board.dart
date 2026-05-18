import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'hoga_pivot_row.dart';
import 'hoga_row.dart';
import 'hoga_status_chip_bar.dart';
import 'hoga_summary_row.dart';
import 'models/hoga_board_model.dart';
import 'services/hoga_api.dart';

typedef HogaRowTap = void Function(int price, HogaSide side, HogaStatus status, HogaGrade? grade);

/// PokeFolio 호가창 메인 위젯.
///
/// 카드 상세에서 사용: `HogaBoard(cardId: card.cardId, onRowTap: ..., onAskRegister: ..., onBidRegister: ...)`
///
/// 1차 출시 (Phase D):
/// - status chip (RAW / PSA10 / BRG)
/// - summary (lowest ask / highest bid / spread / counts)
/// - ASK section (위, 파랑, 가격 내림차순)
/// - pivot row (기준가 + tick unit)
/// - BID section (아래, 초록, 가격 내림차순)
/// - empty state CTA
/// - loading / error / retry
/// - row tap callback (Phase E에서 하단시트 연결)
/// - register callback (Phase F에서 등록 모달 연결)
class HogaBoard extends StatefulWidget {
  final String cardId;
  final HogaRowTap? onRowTap;
  final VoidCallback? onAskRegister;
  final VoidCallback? onBidRegister;

  const HogaBoard({
    super.key,
    required this.cardId,
    this.onRowTap,
    this.onAskRegister,
    this.onBidRegister,
  });

  @override
  State<HogaBoard> createState() => _HogaBoardState();
}

class _HogaBoardState extends State<HogaBoard> {
  HogaStatus _status = HogaStatus.raw;
  HogaGrade? _grade; // PSA/BRG일 때만 사용

  String _cacheKey(HogaStatus s, HogaGrade? g) => s.requiresGrade ? '${s.wire}_${g?.wire ?? "10"}' : s.wire;
  final Map<String, Future<HogaBoardData>> _cache = {};

  Future<HogaBoardData> _load(HogaStatus status, HogaGrade? grade) {
    final key = _cacheKey(status, grade);
    return _cache.putIfAbsent(
      key,
      () => HogaApi.fetchBoard(widget.cardId, status: status, grade: grade),
    );
  }

  void _retry() {
    setState(() => _cache.remove(_cacheKey(_status, _grade)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HogaBoardData>(
      future: _load(_status, _grade),
      builder: (ctx, snap) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1단 + 2단 chip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: HogaStatusChipBar(
                  selectedStatus: _status,
                  selectedGrade: _grade,
                  onChanged: (s, g) {
                    setState(() {
                      _status = s;
                      _grade = g;
                    });
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (snap.connectionState == ConnectionState.waiting)
                _loading()
              else if (snap.hasError)
                _error(snap.error)
              else
                _content(snap.data!),
            ],
          ),
        );
      },
    );
  }

  Widget _loading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );

  Widget _error(Object? e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Center(
          child: Column(
            children: [
              const Text('호가를 불러오지 못했습니다.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              Text('$e',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              const SizedBox(height: 8),
              TextButton(onPressed: _retry, child: const Text('재시도')),
            ],
          ),
        ),
      );

  Widget _content(HogaBoardData board) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: HogaSummaryRow(board: board),
        ),
        const SizedBox(height: 10),
        if (board.isEmpty) _emptyState() else _rows(board),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onAskRegister,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: const BorderSide(color: AppColors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('판매 호가 등록'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onBidRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('매수 호가 등록'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_vert_rounded, color: AppColors.textMuted, size: 36),
              const SizedBox(height: 10),
              const Text(
                '아직 등록된 호가가 없습니다.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                '첫 번째 판매자/매수자가 되어보세요.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      );

  Widget _rows(HogaBoardData board) {
    final asks = board.asks; // 가격 내림차순. 위쪽이 비싼 매도.
    final bids = board.bids; // 가격 내림차순. 위쪽이 비싼 매수.
    final lowestAsk = board.lowestAsk;
    final highestBid = board.highestBid;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final ask in asks)
          HogaRow(
            level: ask,
            side: HogaSide.ask,
            highlight: lowestAsk != null && ask.price == lowestAsk,
            onTap: widget.onRowTap == null
                ? null
                : () => widget.onRowTap!(ask.price, HogaSide.ask, _status, _grade),
          ),
        HogaPivotRow(marketPrice: board.marketPrice, tickUnit: board.tickUnit),
        for (final bid in bids)
          HogaRow(
            level: bid,
            side: HogaSide.bid,
            highlight: highestBid != null && bid.price == highestBid,
            onTap: widget.onRowTap == null
                ? null
                : () => widget.onRowTap!(bid.price, HogaSide.bid, _status, _grade),
          ),
      ],
    );
  }
}
