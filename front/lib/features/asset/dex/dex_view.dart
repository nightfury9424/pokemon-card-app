// 2026-05-29 Phase B — 도감 메인 grid view. asset_screen 의 4번째 탭 내용.
//
// 디자인 (Codex Q6, Q7, Q8 반영):
//   - 3-col BoxCard grid (자산 화면 일관)
//   - hero card 이미지 cover (백엔드가 완성 URL 반환)
//   - 시리즈명 + "N/M 보유" + progress bar
//   - 다크 모드 충돌 방지 — 절제된 shadow, perspective X
//   - 미보유 시리즈도 0/N 으로 표시 (Codex Q7)
//   - 자산 0 신규 유저도 grid 그대로 + 상단 진행도 헤더 (Codex Q8)
//   - 라벨: "추천 시리즈" / "최신 시리즈" (사용자 명시 — "최근 발매" 금지)

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifiers/asset_notifier.dart';
import '../../../core/theme/app_colors.dart';
import 'dex_api.dart';
import 'dex_models.dart';

class DexView extends StatefulWidget {
  /// 2026-05-29 Codex 사후 Q1 — pull-to-refresh 시 부모(asset_screen) 도 같이 reload.
  /// 도감 탭이 다른 탭과 동일하게 portfolio summary 까지 갱신되게.
  ///
  /// 2026-05-29 (fix): nested RefreshIndicator 충돌 해소 — 외부 (asset_screen) 의
  /// RefreshIndicator + CustomScrollView 가 portfolio + 도감 영역 모두 잡음.
  /// DexView 는 자체 RefreshIndicator 제거. 외부에서 GlobalKey 로 reload() 호출.
  final Future<void> Function()? onParentRefresh;
  const DexView({super.key, this.onParentRefresh});

  @override
  State<DexView> createState() => DexViewState();
}

class DexViewState extends State<DexView> {
  /// 외부 (asset_screen) RefreshIndicator 가 GlobalKey 로 호출 — portfolio 와 도감 동기.
  Future<void> reload() => _load();

  void _onAssetChange() {
    // 2026-05-30 stale fix — 자산 변경 broadcast 받으면 도감 자동 reload.
    //   카드 상세 / 스캐너 / 자산 화면에서 추가/수정/삭제 후 도감 즉시 반영.
    if (mounted) _load();
  }

  DexMain? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    AssetNotifier.instance.addListener(_onAssetChange);
    _load();
  }

  @override
  void dispose() {
    AssetNotifier.instance.removeListener(_onAssetChange);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Codex 사후 Q1 — 부모 (asset_screen) reload + 도감 fetch 병렬.
      // 2026-05-30 limit 40 (사용자 명시 — 테라스탈/SV 더 노출).
      await Future.wait([
        if (widget.onParentRefresh != null) widget.onParentRefresh!(),
        DexApi.getDexMain(limit: 40).then((d) => _data = d),
      ]);
      if (mounted) setState(() { _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '도감을 불러오지 못했습니다'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.blueLight));
    }
    if (_error != null || _data == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error ?? '도감 데이터 없음', style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextButton(onPressed: _load, child: const Text('다시 시도')),
        ]),
      );
    }
    final d = _data!;
    // asset_screen 의 외부 RefreshIndicator + CustomScrollView 안 SliverFillRemaining
    // 에 들어감. 자체 CustomScrollView 는 도감 grid 본인 스크롤 처리 (nested).
    // pull-to-refresh 는 외부 (asset_screen) 가 GlobalKey 로 reload() 호출.
    return CustomScrollView(
      slivers: [
          SliverToBoxAdapter(child: _Header(data: d)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.62,    // 세로형 박스카드 (포케몬 카드 비율 참고)
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _BoxCard(item: d.products[i]),
                childCount: d.products.length,
              ),
            ),
          ),
          if (d.hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                child: Text(
                  '추천 시리즈 ${d.products.length}개 표시 · 전체 ${d.totalProducts}개',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ),
            ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final DexMain data;
  const _Header({required this.data});

  @override
  Widget build(BuildContext context) {
    final hasAny = data.totalOwnedCards > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('추천 시리즈',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(width: 8),
              Text('${data.products.length} / ${data.totalProducts}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasAny
                ? '보유 시리즈 ${data.ownedSeriesCount}종 · 보유 카드 ${data.totalOwnedCards}종'
                : '카드를 등록하면 시리즈별 도감 진행도가 채워져요',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// hero 이미지 없거나 S3 miss 시 fallback — 시리즈명 placeholder.
/// Codex 사후 Q4: 그리드 품질 급락 방지.
class _HeroFallback extends StatelessWidget {
  final String name;
  const _HeroFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceElevated, AppColors.surface],
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _BoxCard extends StatelessWidget {
  final DexBoxItem item;
  const _BoxCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final ratio = item.progressRatio;
    final progressColor = ratio >= 1.0
        ? AppColors.gold
        : ratio > 0
            ? AppColors.blueLight
            : AppColors.divider;

    return GestureDetector(
      onTap: () => context.push('/dex/${item.productId}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.5),
          // 절제된 shadow — 다크모드 충돌 방지 (Codex Q6).
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // hero card 이미지 (또는 placeholder). Codex 사후 Q4 — S3 miss/null 시 시리즈명 placeholder.
            Expanded(
              flex: 7,
              child: Container(
                width: double.infinity,
                color: AppColors.bg,
                child: item.heroCardImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.heroCardImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ColoredBox(color: AppColors.surface),
                        errorWidget: (_, __, ___) => _HeroFallback(name: item.productName),
                      )
                    : _HeroFallback(name: item.productName),
              ),
            ),
            // 텍스트 + 진행도.
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${item.ownedCount} / ${item.totalKoVisible}',
                      style: TextStyle(
                        color: ratio > 0 ? AppColors.textPrimary : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: AppColors.dividerSoft,
                        valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
