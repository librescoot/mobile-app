import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/service/photon_service.dart';

import '../support/persistence_fakes.dart';

void main() {
  test('place search and reverse lookup do not contact Photon without consent', () async {
    final previousPrefs = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences()..bools['osmConsent'] = false;
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previousPrefs);

    expect(await photonForwardSearch('Berlin'), isEmpty);
    expect(await photonReverseSearch(52.52, 13.405), isEmpty);
  });
}
