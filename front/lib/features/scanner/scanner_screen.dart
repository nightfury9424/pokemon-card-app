import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _cameraController;

  bool _isProcessing = false;
  bool _cameraReady = false;
  bool _modalShowing = false;
  String _statusText = '카드를 화면에 보여주세요';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _statusText = '카메라 권한이 필요합니다');
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (_cameraController!.value.focusPointSupported) {
      await _cameraController!.setFocusMode(FocusMode.auto);
    }
    if (_cameraController!.value.exposurePointSupported) {
      await _cameraController!.setExposureMode(ExposureMode.auto);
    }
    if (!mounted) return;

    setState(() => _cameraReady = true);
    _scheduleScan();
  }

  void _scheduleScan() {
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (!mounted || !_cameraReady || _isProcessing || _modalShowing) return;
      await _captureAndScan();
    });
  }

  Future<void> _captureAndScan() async {
    if (!mounted || _isProcessing || _cameraController == null || _modalShowing) return;
    _isProcessing = true;
    if (mounted) setState(() => _statusText = '분석 중...');

    try {
      final xFile = await _cameraController!.takePicture();
      final file = File(xFile.path);

      final res = await ApiClient.postMultipart(
        ApiConstants.scannerIdentify,
        files: {'image': file},
      );

      try { file.deleteSync(); } catch (_) {}

      final items = res['data'] as List?;
      if (items == null || items.isEmpty) {
        if (mounted) setState(() => _statusText = '카드를 인식하지 못했습니다');
        return;
      }

      final card = Map<String, dynamic>.from(items.first as Map);
      await _showCardModal(card);
    } catch (e) {
      debugPrint('[Scanner] Error: $e');
      if (mounted) setState(() => _statusText = '오류 — 다시 시도합니다');
    } finally {
      _isProcessing = false;
      if (mounted && !_modalShowing) _scheduleScan();
    }
  }

  Future<void> _showCardModal(Map<String, dynamic> card) async {
    _modalShowing = true;
    if (mounted) setState(() => _statusText = '카드를 찾았습니다!');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CardFoundSheet(
        card: card,
        onContinueScan: () => Navigator.pop(ctx),
        onAddToAsset: (cardId, quantity) async {
          Navigator.pop(ctx);
          await _addToAsset(cardId, quantity);
        },
        onViewDetail: () {
          Navigator.pop(ctx);
          context.push('/card/${card['cardId']}', extra: card);
        },
      ),
    );

    _modalShowing = false;
    if (mounted) {
      setState(() => _statusText = '카드를 화면에 보여주세요');
      _scheduleScan();
    }
  }

  Future<void> _addToAsset(String cardId, int quantity) async {
    try {
      String userId = 'guest';
      try {
        final userRes = await ApiClient.get('/api/users/me');
        userId = (userRes['data'] as Map<String, dynamic>?)?['userId'] as String? ?? 'guest';
      } catch (_) {}

      await ApiClient.post(ApiConstants.assets, {
        'data': {
          'userId': userId,
          'cardId': cardId,
          'quantity': quantity,
          'cardStatus': 'RAW',
          'purchasedAt': DateTime.now().toIso8601String().substring(0, 10),
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('자산에 추가됐습니다'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('추가 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('카드 스캔'),
      ),
      body: Stack(
        children: [
          if (_cameraReady && _cameraController != null)
            Positioned.fill(child: _buildFullScreenPreview()),

          Positioned.fill(child: _buildGuideOverlay()),

          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isProcessing) ...[
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenPreview() {
    final previewSize = _cameraController!.value.previewSize;
    if (previewSize == null) return const ColoredBox(color: Colors.black);
    return OverflowBox(
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  Widget _buildGuideOverlay() => CustomPaint(painter: _GuideBoxPainter());
}

// ─── 카드 인식 하단 모달 ──────────────────────────────────────────────────────

class _CardFoundSheet extends StatefulWidget {
  final Map<String, dynamic> card;
  final VoidCallback onContinueScan;
  final Future<void> Function(String cardId, int quantity) onAddToAsset;
  final VoidCallback onViewDetail;

  const _CardFoundSheet({
    required this.card,
    required this.onContinueScan,
    required this.onAddToAsset,
    required this.onViewDetail,
  });

  @override
  State<_CardFoundSheet> createState() => _CardFoundSheetState();
}

class _CardFoundSheetState extends State<_CardFoundSheet> {
  int _quantity = 1;
  bool _adding = false;

  String? _imageUrl() {
    final jp = widget.card['jpScrydexRef'] as String?;
    if (jp != null && jp.isNotEmpty && jp != 'NO_JP') {
      return 'https://images.scrydex.com/pokemon/$jp/medium';
    }
    final en = widget.card['enScrydexRef'] as String?;
    if (en != null && en.isNotEmpty && en != 'NO_EN') {
      return 'https://images.scrydex.com/pokemon/$en/medium';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.card['name'] as String? ?? '알 수 없는 카드';
    final rarity = widget.card['rarityCode'] as String? ?? '';
    final imgUrl = _imageUrl();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A2340),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 카드 이미지
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imgUrl != null
                    ? Image.network(
                        imgUrl,
                        width: 90, height: 126,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rarity.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.blue.withOpacity(0.4)),
                        ),
                        child: Text(rarity, style: const TextStyle(color: AppColors.blue, fontSize: 11)),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('수량', style: TextStyle(color: Colors.white60, fontSize: 13)),
                        const SizedBox(width: 12),
                        _QtyBtn(icon: Icons.remove, onTap: () {
                          if (_quantity > 1) setState(() => _quantity--);
                        }),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('$_quantity',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        _QtyBtn(icon: Icons.add, onTap: () => setState(() => _quantity++)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _adding ? null : () async {
                setState(() => _adding = true);
                await widget.onAddToAsset(widget.card['cardId'] as String, _quantity);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _adding
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('자산 등록하기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),

          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: widget.onViewDetail,
                  child: const Text('상세 보기', style: TextStyle(color: Colors.white54, fontSize: 14))),
              const Text('·', style: TextStyle(color: Colors.white24)),
              TextButton(onPressed: widget.onContinueScan,
                  child: const Text('계속 스캔', style: TextStyle(color: Colors.white54, fontSize: 14))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 90, height: 126,
    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
    child: const Icon(Icons.style, color: Colors.white24, size: 32),
  );
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)),
      child: Icon(icon, color: Colors.white, size: 16),
    ),
  );
}

// ─── 가이드 박스 ──────────────────────────────────────────────────────────────

class _GuideBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boxH = size.height * 0.65;
    final boxW = boxH / 1.396;
    final left = (size.width - boxW) / 2;
    final top = (size.height - boxH) / 2;

    final bgPaint = Paint()..color = Colors.black45;
    canvas.drawRect(Rect.fromLTWH(0, 0, left, size.height), bgPaint);
    canvas.drawRect(Rect.fromLTWH(left + boxW, 0, size.width - left - boxW, size.height), bgPaint);
    canvas.drawRect(Rect.fromLTWH(left, 0, boxW, top), bgPaint);
    canvas.drawRect(Rect.fromLTWH(left, top + boxH, boxW, size.height - top - boxH), bgPaint);

    final borderPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, boxW, boxH), const Radius.circular(8)),
      borderPaint,
    );

    final cornerPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 20.0;
    canvas.drawLine(Offset(left, top + len), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + len, top), cornerPaint);
    canvas.drawLine(Offset(left + boxW - len, top), Offset(left + boxW, top), cornerPaint);
    canvas.drawLine(Offset(left + boxW, top), Offset(left + boxW, top + len), cornerPaint);
    canvas.drawLine(Offset(left, top + boxH - len), Offset(left, top + boxH), cornerPaint);
    canvas.drawLine(Offset(left, top + boxH), Offset(left + len, top + boxH), cornerPaint);
    canvas.drawLine(Offset(left + boxW, top + boxH - len), Offset(left + boxW, top + boxH), cornerPaint);
    canvas.drawLine(Offset(left + boxW, top + boxH), Offset(left + boxW - len, top + boxH), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
