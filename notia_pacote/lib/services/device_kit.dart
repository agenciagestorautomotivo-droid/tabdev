import 'app_agent_service.dart';
import 'clipboard_history_service.dart';
import 'gallery_service.dart';
import 'local_calendar_service.dart';
import 'lock_service.dart';
import 'notification_service.dart';
import 'ocr_service.dart';
import 'phone_service.dart';
import 'place_service.dart';
import 'power_service.dart';
import 'routine_service.dart';

/// Todos os recursos do aparelho num só objeto, para passar ao console e à CONFIG.
class DeviceKit {
  DeviceKit({
    required this.agent,
    required this.notifs,
    required this.phone,
    required this.ocr,
    required this.gallery,
    required this.localCal,
    required this.clip,
    required this.routines,
    required this.places,
    required this.power,
    required this.lock,
  });
  final AppAgentService agent;
  final NotificationService notifs;
  final PhoneService phone;
  final OcrService ocr;
  final GalleryService gallery;
  final LocalCalendarService localCal;
  final ClipboardHistoryService clip;
  final RoutineService routines;
  final PlaceService places;
  final PowerService power;
  final LockService lock;
}
