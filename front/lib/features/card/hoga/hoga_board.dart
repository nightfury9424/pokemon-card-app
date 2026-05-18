import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'hoga_pivot_row.dart';
import 'hoga_row.dart';
import 'hoga_status_chip_bar.dart';
import 'hoga_summary_row.dart';
import 'models/hoga_board_model.dart';
import 'services/hoga_api.dart';

typedef HogaRowTap = void Function(int price, HogaSide side, HogaStatus status, HogaGrade? grade);

/// PokeFolio 호가창 메인 위젯 — 코인/주식 호가창 스타일 컴팩트 표.
///
/// 외곽 카드 박스 없음. row 중심.
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
  HogaGrade? _grade;

  String _cacheKey(HogaStatus s, HogaGrade? g) =>
      s.requiresGrade ? '${widget.cardId}_${s.wire}_${g?.wire ?? "10"}' : '${widget.cardId}_${s.wire}';
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
  void didUpdateWidget(covariant HogaBoard old) {
    super.didUpdateWidget(old);
    if (old.cardId != widget.cardId) {
      _cache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HogaBoardData>(
      future: _load(_status, _grade),
      builder: (ctx, snap) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // chip
            HogaStatusChipBar(
              selectedStatus: _status,
              selectedGrade: _grade,
              onChanged: (s, g) {
                setState(() {
                  _status = s;
                  _grade = g;
                });
              },
            ),
            const SizedBox(height: 8),
            if (snap.connectionState == ConnectionState.waiting)
              _loading()
            else if (snap.hasError)
              _error(snap.error)
            else
              _content(snap.data!),
          ],
        );
      },
    );
  }

  Widget _loading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );

  Widget _error(Object? e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Column(
            children: [
              const Text('호가를 불러오지 못했습니다.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
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
        HogaSummaryRow(board: board),
        const SizedBox(height: 6),
        // 호가창 row 묶음 (외곽 박스 없이 표처럼)
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider, width: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _tableRows(board),
          ),
        ),
        const SizedBox(height: 10),
        // 등록 버튼 — 가볍게
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: OutlinedButton(
                  onPressed: widget.onAskRegister,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: const BorderSide(color: AppColors.blue, width: 1),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('판매 호가 등록',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: widget.onBidRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('매수 호가 등록',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 호가창 표 행들. 빈 상태도 표 안에서 처리.
  List<Widget> _tableRows(HogaBoardData board) {
    final lowestAsk = board.lowestAsk;
    final highestBid = board.highestBid;
    final rows = <Widget>[];

    // 매도 라벨
    rows.add(_sectionLabel('매도', AppColors.blue, board.askCount));

    if (board.asks.isEmpty) {
      rows.add(_emptyMini('매도 호가 없음'));
    } else {
      for (final ask in board.asks) {
        rows.add(HogaRow(
          level: ask,
          side: HogaSide.ask,
          highlight: lowestAsk != null && ask.price == lowestAsk,
          onTap: widget.onRowTap == null
              ? null
              : () => widget.onRowTap!(ask.price, HogaSide.ask, _status, _grade),
        ));
      }
    }

    rows.add(HogaPivotRow(marketPrice: board.marketPrice, tickUnit: board.tickUnit));

    // 매수 라벨
    rows.add(_sectionLabel('매수', AppColors.green, board.bidCount));

    if (board.bids.isEmpty) {
      rows.add(_emptyMini('매수 호가 없음'));
    } else {
      for (final bid in board.bids) {
        rows.add(HogaRow(
          level: bid,
          side: HogaSide.bid,
          highlight: highestBid != null && bid.price == highestBid,
          onTap: widget.onRowTap == null
              ? null
              : () => widget.onRowTap!(bid.price, HogaSide.bid, _status, _grade),
        ));
      }
    }

    return rows;
  }

  Widget _sectionLabel(String label, Color color, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: const Border(bottom: BorderSide(color: AppColors.dividerSoft, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6),
          ),
          const SizedBox(width: 6),
          Text(
            '$count건',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _emptyMini(String msg) => Container(
        height: 30,
        alignment: Alignment.center,
        child: Text(
          msg,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      );
}
