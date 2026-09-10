import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licenses for fonts shipped in the application bundle to Flutter's
/// license registry, where the existing Licenses screen displays them.
void registerBundledFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final font in _bundledFonts) {
      final text = await rootBundle.loadString(font.licenseAsset);
      yield LicenseEntryWithLineBreaks([font.family], text);
    }
  });
}

const _bundledFonts = [
  (family: 'Inter', licenseAsset: 'assets/fonts/licenses/Inter-OFL.txt'),
  (family: 'Abel', licenseAsset: 'assets/fonts/licenses/Abel-OFL.txt'),
  (family: 'Kode Mono', licenseAsset: 'assets/fonts/licenses/KodeMono-OFL.txt'),
];
