import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'notia_brain.dart';
import 'vault_service.dart';

class ScanResult {
  ScanResult(this.path, this.text);
  final String path;
  final String text;
}

/// OCR no próprio aparelho (ML Kit): 0 tokens, funciona sem internet.
class OcrService {
  OcrService(this.brain);
  final NotiaBrain brain;
  String lastError = '';

  Future<String?> readFile(String path) async {
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final r = await rec.processImage(InputImage.fromFilePath(path));
      return r.text.trim();
    } catch (e) {
      lastError = 'OCR falhou: $e';
      return null;
    } finally {
      rec.close();
    }
  }

  /// Abre a câmera do sistema, lê o texto e guarda a foto em Midia/Imagens.
  Future<ScanResult?> scanCamera() async {
    lastError = '';
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      if (x == null) return null;
      return await _keep(x.path);
    } catch (e) {
      lastError = 'Câmera indisponível: $e';
      return null;
    }
  }

  /// Lê o texto de uma imagem já salva (ex.: recebida por Compartilhar).
  Future<ScanResult?> scanFile(String path) => _keep(path);

  Future<ScanResult?> _keep(String path) async {
    final text = await readFile(path);
    if (text == null) return null;
    var saved = path;
    if (brain.vault.available) {
      try {
        final dir = Directory('${VaultService.root}/Midia/Imagens');
        await dir.create(recursive: true);
        saved = '${dir.path}/scan-${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(path).copy(saved);
      } catch (_) {
        saved = path;
      }
    }
    return ScanResult(saved, text);
  }
}
