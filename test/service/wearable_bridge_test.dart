import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearable_bridge/wearable_bridge.dart';

void main() {
  const channel = MethodChannel('org.librescoot.mobile/companion');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  testWidgets('snapshot publication coalesces notifications and reads the latest value', (tester) async {
    final bridge = WearableBridge((_) async => 'unavailable');
    var value = 'stand-by';
    bridge.scheduleSnapshot(() => {'state': value});
    value = 'parked';
    bridge.scheduleSnapshot(() => {'state': value});
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls.where((call) => call.method == 'snapshot'), hasLength(1));
    expect(calls.single.arguments, {'state': 'parked'});
    bridge.dispose();
    await tester.pump();
  });
  testWidgets('disposal cancels pending publication and detaches the owner', (tester) async {
    final bridge = WearableBridge((_) async => 'unavailable');
    bridge.scheduleSnapshot(() => {'scooterId': 'a'});
    bridge.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls.map((call) => call.method), ['detach']);
  });
  testWidgets('no target publishes nothing', (tester) async {
    final bridge = WearableBridge((_) async => 'unavailable');
    bridge.scheduleSnapshot(() => null);
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, isEmpty);
    bridge.dispose();
    await tester.pump();
  });
}
