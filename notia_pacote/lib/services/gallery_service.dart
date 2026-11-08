import 'dart:io';

import 'notia_brain.dart';
import 'ocr_service.dart';
import 'text_utils.dart';

/// Busca nas fotos do aparelho. A listagem é por data (grátis). A busca por conteúdo
/// ("a foto da nota fiscal") usa um índice de OCR feito no aparelho: você roda
/// "indexar galeria" e o texto de cada foto fica no SQLite.
class GalleryService {
  GalleryService(this.brain, this.ocr);
  final NotiaBrain brain;
  final OcrService ocr;

  static const _roots = ['/sdcard/DCIM', '/sdcard/Pictures', '/sdcard/Download'];
  static final _ext = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

  Future<List<File>> recent({int n = 30, Duration? within}) async {
    final out = <File>[];
    final limit = within == null ? null : DateTime.now().subtract(within);
    for (final r in _roots) {
      final d = Directory(r);
      if (!await d.exists()) continue;
      try {
        await for (final e in d.list(recursive: true, followLinks: false)) {
          if (e is File && _ext.hasMatch(e.path)) {
            if (limit == null || e.lastModifiedSync().isAfter(limit)) out.add(e);
          }
        }
      } catch (_) {}
    }
    out.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return out.take(n).toList();
  }

  /// Roda OCR nas fotos mais recentes ainda não indexadas. Retorna quantas entraram.
  Future<int> indexOcr({int max = 40, void Function(String msg)? progress}) async {
    final files = await recent(n: 200);
    var done = 0;
    for (final f in files) {
      if (done >= max) break;
      final key = 'ocr:${f.path}:${f.lastModifiedSync().millisecondsSinceEpoch}';
      if (await brain.getKv(key) != null) continue;
      final t = await ocr.readFile(f.path);
      await brain.setKv(key, clip((t ?? '').replaceAll(RegExp(r'\s+'), ' '), 600), categoria: 'ocr');
      done++;
      if (done % 10 == 0) progress?.call('Indexei $done fotos…');
    }
    return done;
  }

  /// Caminhos de fotos cujo texto contém [term].
  Future<List<String>> search(String term) async {
    final rows = await brain.searchKv('ocr:', term);
    final out = <String>[];
    for (final r in rows) {
      final k = r['chave'] as String;
      final p = k.substring(4, k.lastIndexOf(':'));
      if (await File(p).exists()) out.add(p);
    }
    return out;
  }
}
