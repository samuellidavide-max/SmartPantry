// Prepara le cartelle android/ e ios/ e aggiunge permessi e impostazioni di rete.
// Uso (dalla cartella app/):   dart run tool/setup_platforms.dart
//
// Cosa fa:
//  1. flutter create --platforms=android,ios (crea solo i file mancanti, non tocca lib/)
//  2. Android: permessi INTERNET e posizione, traffico HTTP in chiaro (serve per il backend locale)
//  3. iOS: testi per posizione/fotocamera/galleria, HTTP locale consentito
import 'dart:io';

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Esegui lo script dalla cartella app/ (dove c\'è pubspec.yaml).');
    exit(1);
  }
  stdout.writeln('> flutter create --platforms=android,ios .');
  final r = await Process.run(
    'flutter',
    ['create', '--platforms=android,ios', '--org', 'it.smartpantry', '--project-name', 'smartpantry', '.'],
    runInShell: true,
  );
  stdout.write(r.stdout);
  if (r.exitCode != 0) {
    stderr.write(r.stderr);
    exit(r.exitCode);
  }
  // flutter create aggiunge un test d'esempio che usa MyApp (non esiste in questo progetto)
  final sample = File('test/widget_test.dart');
  if (sample.existsSync() && sample.readAsStringSync().contains('MyApp')) sample.deleteSync();
  _patchAndroid();
  _patchIos();
  stdout.writeln('\nFatto. Ora: flutter pub get  e  flutter run');
}

void _patchAndroid() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stderr.writeln('AndroidManifest.xml non trovato, salto Android');
    return;
  }
  var s = f.readAsStringSync();
  const perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_FINE_LOCATION',
  ];
  for (final p in perms) {
    if (!s.contains(p)) {
      s = s.replaceFirst('<application', '<uses-permission android:name="$p"/>\n    <application');
    }
  }
  if (!s.contains('usesCleartextTraffic')) {
    s = s.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"');
  }
  f.writeAsStringSync(s);
  stdout.writeln('Android: permessi e HTTP locale configurati');
}

void _patchIos() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) {
    stderr.writeln('Info.plist non trovato, salto iOS');
    return;
  }
  var s = f.readAsStringSync();
  final entries = <String, String>{
    'NSLocationWhenInUseUsageDescription':
        '<string>Serve per trovare i supermercati vicino a te.</string>',
    'NSCameraUsageDescription': '<string>Serve per fotografare lo scontrino.</string>',
    'NSPhotoLibraryUsageDescription': '<string>Serve per scegliere la foto di uno scontrino.</string>',
    'NSAppTransportSecurity':
        '<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>',
  };
  final buf = StringBuffer();
  entries.forEach((k, v) {
    if (!s.contains('<key>$k</key>')) buf.write('\t<key>$k</key>\n\t$v\n');
  });
  final idx = s.lastIndexOf('</dict>');
  if (idx > 0 && buf.isNotEmpty) {
    s = '${s.substring(0, idx)}$buf${s.substring(idx)}';
    f.writeAsStringSync(s);
  }
  stdout.writeln('iOS: permessi e HTTP locale configurati');
}
