import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../utils/barcode_util.dart';

class BarcodeScannerWidget extends StatefulWidget {
  final Function(String barcode, String format) onScan;
  final bool continuous;
  final String? title;
  final MobileScannerController? externalController;

  const BarcodeScannerWidget({
    super.key,
    required this.onScan,
    this.continuous = false,
    this.title,
    this.externalController,
  });

  @override
  State<BarcodeScannerWidget> createState() => _BarcodeScannerWidgetState();
}

class _BarcodeScannerWidgetState extends State<BarcodeScannerWidget> {
  late MobileScannerController controller;
  bool _isProcessing = false;
  String? _lastBarcode;

  @override
  void initState() {
    super.initState();
    controller = widget.externalController ?? MobileScannerController();
  }

  void pauseScanning() {
    if (mounted) {
      controller.stop();
      setState(() { _isProcessing = true; });
    }
  }

  void resumeScanning() {
    if (mounted) {
      controller.start();
      setState(() { _isProcessing = false; });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing && !widget.continuous) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!;
    final normalized = BarcodeUtil.normalizeBarcode(rawValue);
    if (normalized == null) return;

    if (!widget.continuous && normalized == _lastBarcode) return;

    setState(() {
      _isProcessing = true;
      _lastBarcode = normalized;
    });

    final format = BarcodeUtil.detectFormat(normalized);
    widget.onScan(normalized, format);

    if (!widget.continuous) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
      });
    } else {
      // ★ 连续模式下增加去抖时间到1500ms，配合父界面的_isHandlingBarcode防止重复弹窗
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _isProcessing = false);
      });
    }
  }

  @override
  void dispose() {
    if (widget.externalController == null) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '扫描条码'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: controller.torchState,
              builder: (context, state, child) {
                return Icon(
                  state == TorchState.on ? Icons.flash_on : Icons.flash_off,
                );
              },
            ),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: controller.cameraFacingState,
              builder: (context, state, child) {
                return Icon(
                  state == CameraFacing.front
                      ? Icons.camera_front
                      : Icons.camera_rear,
                );
              },
            ),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      '摄像头启动失败',
                      style: TextStyle(color: Colors.red.shade300, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请检查摄像头权限是否已开启',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    ),
                  ],
                ),
              );
            },
            placeholderBuilder: (context, child) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('正在启动摄像头...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              );
            },
            overlay: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.green,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(40),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '将条码对准扫描框',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
          if (_isProcessing && !widget.continuous)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class ManualBarcodeInput extends StatefulWidget {
  final Function(String)? onSubmit;

  const ManualBarcodeInput({super.key, this.onSubmit});

  @override
  State<ManualBarcodeInput> createState() => _ManualBarcodeInputState();
}

class _ManualBarcodeInputState extends State<ManualBarcodeInput> {
  final _controller = TextEditingController();

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      widget.onSubmit?.call(value);
      Navigator.pop(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('手动输入条码或商品名'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.text,
        decoration: const InputDecoration(
          hintText: '请输入商品条码或名称',
          prefixIcon: Icon(Icons.qr_code),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('确认'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
