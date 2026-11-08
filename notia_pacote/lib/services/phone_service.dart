import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'text_utils.dart';

class FoundContact {
  FoundContact(this.name, this.number);
  final String name;
  final String number;
}

/// Contatos, ligação, SMS e WhatsApp. Ligar e enviar sempre abre a tela do app
/// já preenchida: você toca em ligar/enviar (nada sai sem você).
class PhoneService {
  String lastError = '';

  Future<FoundContact?> find(String query) async {
    lastError = '';
    try {
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        lastError = 'Sem permissão de contatos. Libere em Configurações > Apps > Notia.';
        return null;
      }
      final all = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
      final q = norm(query.trim());
      Contact? best;
      for (final c in all) {
        if (c.phones.isEmpty) continue;
        final n = norm(c.displayName);
        if (n == q) {
          best = c;
          break;
        }
        if (best == null && n.contains(q)) best = c;
      }
      if (best == null) {
        lastError = 'Não achei "$query" nos contatos.';
        return null;
      }
      return FoundContact(best.displayName, best.phones.first.number);
    } catch (e) {
      lastError = 'Contatos indisponíveis: $e';
      return null;
    }
  }

  String _digits(String n) {
    var d = n.replaceAll(RegExp(r'[^0-9+]'), '');
    if (!d.startsWith('+')) {
      d = d.replaceFirst(RegExp(r'^0+'), '');
      if (d.length <= 11) d = '55$d';
    } else {
      d = d.substring(1);
    }
    return d;
  }

  Future<bool> dial(FoundContact c) =>
      launchUrl(Uri(scheme: 'tel', path: c.number), mode: LaunchMode.externalApplication);

  Future<bool> sms(FoundContact c, String body) => launchUrl(
      Uri(scheme: 'sms', path: c.number, queryParameters: body.isEmpty ? null : {'body': body}),
      mode: LaunchMode.externalApplication);

  Future<bool> whatsapp(FoundContact c, String body) => launchUrl(
      Uri.parse('https://wa.me/${_digits(c.number)}${body.isEmpty ? '' : '?text=${Uri.encodeComponent(body)}'}'),
      mode: LaunchMode.externalApplication);
}
