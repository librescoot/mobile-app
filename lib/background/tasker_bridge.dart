import 'package:shared_preferences/shared_preferences.dart';

/// Tasker request id, persisted with the existing widget action slot so the
/// service can pair an action with the request waiting on it. Widget taps leave
/// it absent.
const String pendingWidgetActionRequestIdKey = "pendingWidgetActionRequestId";

/// Results are stored as `actionResult.<requestId>` -> `<epochMillis>:<result>`.
const String taskerResultPrefix = "actionResult.";

const String taskerResultOk = "ok";
const String taskerResultNotConnected = "not_connected";
const String taskerResultNoScooterSaved = "no_scooter_saved";
const String taskerResultServiceBlocked = "service_blocked";
const String taskerResultUnsupportedAction = "unsupported_action";
const String taskerResultFailedPrefix = "failed:";

/// How long an uncollected result stays before it is swept.
const Duration _resultRetention = Duration(minutes: 10);

/// Describes a thrown failure in the plugin's vocabulary. The transport throws
/// plain strings when the link isn't there, which is worth telling apart from a
/// command that went out and then went wrong.
String taskerResultForError(Object error) {
  final message = error.toString();
  final missingLink = message.contains("Scooter not found") ||
      message.contains("Scooter not connected") ||
      message.contains("Scooter disconnected") ||
      message.contains("Could not send command");
  return missingLink ? taskerResultNotConnected : "$taskerResultFailedPrefix$error";
}

/// Clears the armed slot if it still belongs to [requestId], then answers it.
/// Used when nothing will run the request, so a later service start cannot
/// replay it.
Future<void> dropAndReport(String requestId, String result) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (prefs.getString(pendingWidgetActionRequestIdKey) == requestId) {
    await prefs.setBool("pendingWidgetAction", false);
    await prefs.remove("pendingWidgetActionName");
    await prefs.remove(pendingWidgetActionRequestIdKey);
  }
  await publishActionResult(requestId, result);
}

/// Records [result] for the waiting Tasker receiver. Results are stored as
/// `<epochMillis>:<result>` so stale entries age out.
Future<void> publishActionResult(String requestId, String result) async {
  final prefs = await SharedPreferences.getInstance();
  // Other isolates may have added result keys since this one last looked.
  await prefs.reload();
  final now = DateTime.now().millisecondsSinceEpoch;
  final key = "$taskerResultPrefix$requestId";
  await prefs.setString(key, "$now:$result");

  for (final stale in prefs.getKeys().toList()) {
    if (stale == key || !stale.startsWith(taskerResultPrefix)) continue;
    final written = int.tryParse(prefs.getString(stale)?.split(":").first ?? "");
    if (written == null || now - written > _resultRetention.inMilliseconds) {
      await prefs.remove(stale);
    }
  }
}
