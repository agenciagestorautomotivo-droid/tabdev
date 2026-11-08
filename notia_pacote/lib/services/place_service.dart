import 'dart:convert';

import 'package:geolocator/geolocator.dart';

import 'settings_store.dart';
import 'text_utils.dart';

class Place {
  Place(this.name, this.lat, this.lon, {this.radius = 150});
  final String name;
  final double lat;
  final double lon;
  final double radius;
  Map<String, dynamic> toJson() => {'n': name, 'la': lat, 'lo': lon, 'r': radius};
  static Place fromJson(Map<String, dynamic> j) => Place('${j['n']}', (j['la'] as num).toDouble(),
      (j['lo'] as num).toDouble(),
      radius: (j['r'] as num?)?.toDouble() ?? 150);
}

/// Lugares salvos (casa, trabalho...). Quando você chega a um deles, o Notia dispara as
/// rotinas "local <nome>". Usa localização aproximada, só com o Notia aberto.
class PlaceService {
  PlaceService(this.settings) {
    try {
      final l = jsonDecode(settings.placesJson) as List;
      _places = [for (final e in l) Place.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      _places = [];
    }
  }
  final SettingsStore settings;
  late List<Place> _places;
  String? current;
  String lastError = '';

  List<Place> get places => List.unmodifiable(_places);

  Future<Position?> _position() async {
    lastError = '';
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        lastError = 'Sem permissão de localização.';
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        lastError = 'A localização do aparelho está desligada.';
        return null;
      }
      return await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)));
    } catch (e) {
      lastError = 'Localização indisponível: $e';
      return null;
    }
  }

  Future<bool> saveHere(String name) async {
    final pos = await _position();
    if (pos == null) return false;
    final n = norm(name.trim());
    _places.removeWhere((e) => e.name == n);
    _places.add(Place(n, pos.latitude, pos.longitude));
    await settings.setPlacesJson(jsonEncode(_places.map((e) => e.toJson()).toList()));
    current = n;
    return true;
  }

  Future<void> remove(String name) async {
    _places.removeWhere((e) => e.name == norm(name));
    await settings.setPlacesJson(jsonEncode(_places.map((e) => e.toJson()).toList()));
  }

  /// Verifica onde você está. Se acabou de chegar a um lugar salvo, devolve o nome.
  Future<String?> checkArrival() async {
    if (_places.isEmpty) return null;
    final pos = await _position();
    if (pos == null) return null;
    String? here;
    for (final p in _places) {
      if (Geolocator.distanceBetween(pos.latitude, pos.longitude, p.lat, p.lon) <= p.radius) {
        here = p.name;
        break;
      }
    }
    final arrived = here != null && here != current ? here : null;
    current = here;
    return arrived;
  }
}
