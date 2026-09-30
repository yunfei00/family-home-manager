import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/app_database.dart';
import '../models.dart';
import '../qr.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({
    super.key,
    this.title = '扫描位置二维码',
  });

  final String title;

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handling = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '闪光灯',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on_outlined),
          ),
          IconButton(
            tooltip: '切换摄像头',
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _message ?? '把柜子、抽屉或收纳箱上的二维码放进方框。',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    final code = parseLocationQrPayload(raw);
    if (code == null) {
      setState(() => _message = '这不是 Family Home Manager 的位置二维码。');
      return;
    }

    _handling = true;
    final location = await AppDatabase.instance.getLocationByCode(code);
    if (!mounted) return;

    if (location == null) {
      setState(() => _message = '二维码有效，但本机没有找到这个位置。');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      _handling = false;
      return;
    }

    Navigator.of(context).pop<LocationNode>(location);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
