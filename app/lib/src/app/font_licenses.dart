import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The OFL asks that its text travel with the fonts. Registering it puts it on
/// the platform licence page next to the package licences, which is where a
/// reader would look for it.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (package, path) in _licences) {
      final text = await rootBundle.loadString(path);
      yield LicenseEntryWithLineBreaks([package], text);
    }
  });
}

const _licences = [
  ('Gowun Batang', 'assets/fonts/gowun_batang/OFL.txt'),
  ('Nanum Pen Script', 'assets/fonts/nanum_pen_script/OFL.txt'),
];
