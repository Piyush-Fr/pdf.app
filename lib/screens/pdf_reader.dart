import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key, required this.bytes, this.filename});
  final Uint8List bytes;
  final String? filename;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.bytes),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.filename ?? 'PDF'),
          backgroundColor: Colors.transparent,
        ),
        body: PdfViewPinch(controller: _controller),
      ),
    );
  }
}



