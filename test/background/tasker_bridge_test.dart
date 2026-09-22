import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/background/tasker_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('publishActionResult records a timestamped result the receiver can read', () async {
    await publishActionResult('req-1', taskerResultOk);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${taskerResultPrefix}req-1');
    expect(raw, isNotNull);
    expect(raw!.split(':').last, taskerResultOk);
    expect(int.parse(raw.split(':').first), greaterThan(0));
  });

  test('only uncollected results older than the retention window are swept', () async {
    final prefs = await SharedPreferences.getInstance();
    final old = DateTime.now().subtract(const Duration(minutes: 11)).millisecondsSinceEpoch;
    await prefs.setString('${taskerResultPrefix}old', '$old:$taskerResultOk');
    await prefs.setString('pendingWidgetActionName', 'lock');

    await publishActionResult('new', taskerResultOk);

    expect(prefs.getString('${taskerResultPrefix}old'), isNull);
    expect(prefs.getString('${taskerResultPrefix}new'), isNotNull);
    // Non-result keys must survive the sweep.
    expect(prefs.getString('pendingWidgetActionName'), 'lock');
  });

  test('a missing link is reported differently from a command that went wrong', () {
    expect(taskerResultForError('Scooter disconnected!'), taskerResultNotConnected);
    expect(taskerResultForError('Scooter not found!'), taskerResultNotConnected);
    expect(taskerResultForError('Scooter not connected!'), taskerResultNotConnected);
    expect(taskerResultForError('Failed to lock, response: nope'), 'failed:Failed to lock, response: nope');
  });

  test('dropAndReport disarms the slot and answers the waiting request', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pendingWidgetActionName', 'lock');
    await prefs.setString(pendingWidgetActionRequestIdKey, 'req-1');
    await prefs.setBool('pendingWidgetAction', true);

    await dropAndReport('req-1', taskerResultNoScooterSaved);

    expect(prefs.getBool('pendingWidgetAction'), false);
    expect(prefs.getString('pendingWidgetActionName'), isNull);
    expect(prefs.getString(pendingWidgetActionRequestIdKey), isNull);
    expect(prefs.getString('${taskerResultPrefix}req-1')!.split(':').last, taskerResultNoScooterSaved);
  });

  test('dropAndReport leaves a slot another request has since claimed', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pendingWidgetActionName', 'unlock');
    await prefs.setString(pendingWidgetActionRequestIdKey, 'req-2');
    await prefs.setBool('pendingWidgetAction', true);

    await dropAndReport('req-1', taskerResultOk);

    expect(prefs.getBool('pendingWidgetAction'), true);
    expect(prefs.getString('pendingWidgetActionName'), 'unlock');
    expect(prefs.getString(pendingWidgetActionRequestIdKey), 'req-2');
    expect(prefs.getString('${taskerResultPrefix}req-1'), isNotNull);
  });
}
