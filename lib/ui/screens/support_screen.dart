import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:unustasis/domain/log_helper.dart';
import 'package:unustasis/domain/nav_destination.dart';
import 'package:unustasis/ui/widgets/header.dart';
import 'package:unustasis/ui/screens/navigation_screen.dart';

const _handbookUrl = 'https://librescoot.org/handbook/';
const _troubleshootingUrl = 'https://librescoot.org/handbook/troubleshooting.html';
const _discordUrl = 'https://discord.gg/BmY2P2T9j3';
const _issuesUrl = 'https://github.com/librescoot/mobile-app/issues';
const _partsUrl = 'https://shop.librescoot.org/';
const _websiteUrl = 'https://librescoot.org/';
const _sourceUrl = 'https://github.com/librescoot/mobile-app';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final Future<PackageInfo> _packageInfoFuture = PackageInfo.fromPlatform();

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Widget _linkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: const Icon(Icons.open_in_new_rounded, size: 20),
      onTap: () => _open(url),
    );
  }

  Widget _tileGroup(List<Widget> children) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0)
            Divider(
              indent: 16,
              endIndent: 16,
              height: 24,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          children[index],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(FlutterI18n.translate(context, 'stats_title_support'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.only(bottom: 24 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            Header(
              FlutterI18n.translate(context, 'support_guides'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            ),
            _tileGroup([
              _linkTile(
                icon: Icons.menu_book_outlined,
                title: FlutterI18n.translate(context, 'support_handbook'),
                subtitle: FlutterI18n.translate(context, 'support_handbook_description'),
                url: _handbookUrl,
              ),
              _linkTile(
                icon: Icons.build_circle_outlined,
                title: FlutterI18n.translate(context, 'support_troubleshooting'),
                subtitle: FlutterI18n.translate(context, 'support_troubleshooting_description'),
                url: _troubleshootingUrl,
              ),
            ]),
            Header(FlutterI18n.translate(context, 'support_faqs')),
            const FaqWidget(),
            Header(FlutterI18n.translate(context, 'support_community')),
            _tileGroup([
              _linkTile(
                icon: Icons.discord_outlined,
                title: FlutterI18n.translate(context, 'support_discord'),
                subtitle: FlutterI18n.translate(context, 'support_discord_description'),
                url: _discordUrl,
              ),
              ListTile(
                leading: const Icon(Icons.attach_email_outlined),
                title: Text(
                  FlutterI18n.translate(context, 'support_send_debug_logs'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18),
                ),
                subtitle: Text(
                  FlutterI18n.translate(context, 'settings_report_description'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => LogHelper.startBugReport(context),
              ),
              _linkTile(
                icon: Icons.bug_report_outlined,
                title: FlutterI18n.translate(context, 'support_github_issues'),
                subtitle: FlutterI18n.translate(context, 'support_github_issues_description'),
                url: _issuesUrl,
              ),
            ]),
            Header(
              FlutterI18n.translate(context, 'support_repairs_parts'),
              subtitle: FlutterI18n.translate(context, 'support_garages_description'),
            ),
            const GarageWidget(),
            const SizedBox(height: 8),
            _tileGroup([
              _linkTile(
                icon: Icons.handyman_outlined,
                title: FlutterI18n.translate(context, 'support_replacement_parts'),
                subtitle: FlutterI18n.translate(context, 'support_replacement_parts_description'),
                url: _partsUrl,
              ),
            ]),
            Header(
              FlutterI18n.translate(context, 'stats_settings_section_about'),
              subtitle: FlutterI18n.translate(context, 'support_about_description'),
            ),
            _tileGroup([
              _linkTile(
                icon: Icons.public_rounded,
                title: FlutterI18n.translate(context, 'support_website'),
                subtitle: FlutterI18n.translate(context, 'support_website_description'),
                url: _websiteUrl,
              ),
              _linkTile(
                icon: Icons.code_rounded,
                title: FlutterI18n.translate(context, 'support_source_code'),
                subtitle: FlutterI18n.translate(context, 'support_source_code_description'),
                url: _sourceUrl,
              ),
              FutureBuilder<PackageInfo>(
                future: _packageInfoFuture,
                builder: (context, packageInfo) => ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(FlutterI18n.translate(context, 'settings_app_version')),
                  subtitle: Text(
                    packageInfo.hasData ? '${packageInfo.data!.version} (${packageInfo.data!.buildNumber})' : '…',
                  ),
                ),
              ),
              FutureBuilder<PackageInfo>(
                future: _packageInfoFuture,
                builder: (context, packageInfo) => ListTile(
                  leading: const Icon(Icons.balance_outlined),
                  title: Text(FlutterI18n.translate(context, 'settings_licenses')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: packageInfo.hasData ? packageInfo.data!.appName : 'Librescoot App for unu',
                    applicationVersion: packageInfo.hasData ? packageInfo.data!.version : '?.?.?',
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class FaqWidget extends StatelessWidget {
  const FaqWidget({super.key});

  Future<Map<String, dynamic>> _load(BuildContext context, String languageCode) async {
    final bundle = DefaultAssetBundle.of(context);
    try {
      final data = await bundle.loadString('assets/faq_$languageCode.json');
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      final data = await bundle.loadString('assets/faq_en.json');
      return jsonDecode(data) as Map<String, dynamic>;
    }
  }

  IconData _categoryIcon(int index) => switch (index) {
        0 => Icons.rocket_launch_outlined,
        1 => Icons.bluetooth_searching_rounded,
        2 => Icons.local_fire_department_outlined,
        _ => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _load(context, FlutterI18n.currentLocale(context)?.languageCode ?? 'en'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Text(FlutterI18n.translate(context, 'support_faq_load_error')),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(height: 96, child: Center(child: CircularProgressIndicator()));
        }

        final entries = snapshot.data!.entries.toList();
        return Column(
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              if (index > 0)
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 24,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                ),
              ExpansionTile(
                leading: Icon(_categoryIcon(index)),
                title: Text(
                  entries[index].key,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18),
                ),
                children: [
                  for (final question in (entries[index].value as Map<String, dynamic>).entries.indexed) ...[
                    if (question.$1 > 0)
                      Divider(
                        indent: 60,
                        endIndent: 16,
                        height: 1,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                      ),
                    ExpansionTile(
                      tilePadding: const EdgeInsets.fromLTRB(60, 2, 20, 2),
                      childrenPadding: const EdgeInsets.fromLTRB(60, 0, 20, 16),
                      title: Text(
                        question.$2.key,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _LinkedFaqText(question.$2.value.toString()),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LinkedFaqText extends StatefulWidget {
  const _LinkedFaqText(this.text);

  final String text;

  @override
  State<_LinkedFaqText> createState() => _LinkedFaqTextState();
}

class _LinkedFaqTextState extends State<_LinkedFaqText> {
  static final _linkPattern = RegExp(r'\[([^\]]+)\]\((https?://[^)]+)\)');
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(covariant _LinkedFaqText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _disposeRecognizers();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.5,
        );
    final linkStyle = baseStyle?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );
    final spans = <InlineSpan>[];
    var end = 0;
    for (final match in _linkPattern.allMatches(widget.text)) {
      if (match.start > end) spans.add(TextSpan(text: widget.text.substring(end, match.start)));
      final url = match.group(2)!;
      final recognizer = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url));
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: match.group(1), style: linkStyle, recognizer: recognizer));
      end = match.end;
    }
    if (end < widget.text.length) spans.add(TextSpan(text: widget.text.substring(end)));

    return SelectableText.rich(TextSpan(style: baseStyle, children: spans));
  }
}

class GarageWidget extends StatefulWidget {
  const GarageWidget({super.key});

  @override
  State<GarageWidget> createState() => _GarageWidgetState();
}

class _GarageWidgetState extends State<GarageWidget> {
  Future<List<Garage>>? _garages;

  Future<List<Garage>> _getGarages() async {
    final response = await http
        .get(Uri.parse('https://librescoot.org/unu-garages-data/garages_v2.json'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      Logger('GarageWidget').severe('Failed to load community garages', response.toString());
      throw Exception('Failed to load community garages');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return ((data['garages'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((garage) {
          try {
            return Garage.fromJson(garage);
          } catch (_) {
            return null;
          }
        })
        .whereType<Garage>()
        .toList();
  }

  Future<Position> _getPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabledException();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException('Location permission denied');
    }
    return await Geolocator.getLastKnownPosition() ??
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 12),
          ),
        );
  }

  Future<List<Garage>> _getClosestGarages() async {
    final garages = await _getGarages();
    if (garages.isEmpty) return garages;

    try {
      final position = await _getPosition();
      for (final garage in garages) {
        garage.distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          garage.location.latitude,
          garage.location.longitude,
        );
      }
      garages.sort((a, b) => a.distance!.compareTo(b.distance!));
    } on Exception catch (error) {
      Logger('GarageWidget').info('Showing community garages without distance sorting: $error');
    }
    return garages;
  }

  void _load() {
    setState(() {
      _garages = _getClosestGarages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final garages = _garages;
    if (garages == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.location_searching_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  FlutterI18n.translate(context, 'support_garages_find_description'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.near_me_outlined),
                label: Text(FlutterI18n.translate(context, 'support_garages_find')),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<List<Garage>>(
      future: garages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.location_off_outlined, size: 32, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  Text(
                    FlutterI18n.translate(context, 'support_garages_load_error'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(FlutterI18n.translate(context, 'support_garages_retry')),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            margin: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(height: 144, child: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.data!.isEmpty) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(FlutterI18n.translate(context, 'support_garages_none')),
            ),
          );
        }
        final garages = snapshot.data!;
        final closest = garages.first;
        final nearby =
            garages.skip(1).where((garage) => garage.distance != null && garage.distance! <= 100000).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _GarageTile(garage: closest),
            ),
            if (nearby.isNotEmpty)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: const Icon(Icons.list_alt_rounded),
                title: Text(
                  FlutterI18n.translate(
                    context,
                    'support_garages_more_nearby',
                    translationParams: {'count': nearby.length.toString()},
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _GarageListScreen(garages: [closest, ...nearby]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GarageTile extends StatelessWidget {
  const _GarageTile({required this.garage});

  final Garage garage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(garage.name,
                      style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text('${garage.street}, ${garage.city}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  if (garage.distance != null) ...[
                    Text(
                      FlutterI18n.translate(
                        context,
                        'support_garage_distance',
                        translationParams: {'dist': (garage.distance! / 1000).toStringAsFixed(1)},
                      ),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NavigationScreen(
                                initialDestination: NavDestination(location: garage.location, name: garage.name),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.navigation_outlined),
                          label: Text(FlutterI18n.translate(context, 'support_garage_navigate')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: FlutterI18n.translate(context, 'support_garage_map'),
                        onPressed: () => MapsLauncher.launchQuery('${garage.name} ${garage.street}, ${garage.zipCode}'),
                        icon: const Icon(Icons.map_outlined),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: FlutterI18n.translate(context, 'support_garage_website'),
                        onPressed: garage.website == null
                            ? null
                            : () => launchUrl(Uri.parse(garage.website!), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.language_rounded),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: FlutterI18n.translate(context, 'support_garage_call'),
                        onPressed:
                            garage.phone == 'Unknown' ? null : () => launchUrl(Uri(scheme: 'tel', path: garage.phone)),
                        icon: const Icon(Icons.phone_outlined),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (garage.isDealer) const Positioned(top: 0, right: 0, child: _DealerRibbon()),
          ],
        ),
      ),
    );
  }
}

class _DealerRibbon extends StatelessWidget {
  const _DealerRibbon();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: FlutterI18n.translate(context, 'support_garage_dealer'),
      child: SizedBox(
        width: 56,
        height: 56,
        child: ClipRect(
          child: Center(
            child: Transform.translate(
              // Shifts the rotated band so it crosses the top-right corner.
              offset: const Offset(8, -8),
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 80,
                  height: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GarageListScreen extends StatelessWidget {
  const _GarageListScreen({required this.garages});

  final List<Garage> garages;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(FlutterI18n.translate(context, 'support_garages'))),
      body: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        itemCount: garages.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _GarageTile(garage: garages[index]),
      ),
    );
  }
}

class Garage {
  Garage({
    required this.name,
    required this.phone,
    required this.street,
    required this.city,
    required this.countryCode,
    required this.zipCode,
    required this.location,
    this.website,
    this.isDealer = false,
  });

  String name;
  String phone;
  String street;
  String city;
  String countryCode;
  String zipCode;
  LatLng location;
  double? distance;
  String? website;
  bool isDealer;

  /// Parses the compact format of
  /// https://github.com/librescoot/unu-garages-data (n=name, p=phone,
  /// s=street, z=postal code, c=city, cc=country code, ll=[lat,lng],
  /// w=website, d=official unu dealer).
  /// Throws for entries without valid coordinates; callers skip those.
  factory Garage.fromJson(Map<String, dynamic> json) {
    try {
      final ll = json['ll'] as List<dynamic>;
      return Garage(
        name: json['n']?.isNotEmpty == true ? json['n'] as String : 'Unnamed',
        phone: json['p']?.isNotEmpty == true ? json['p'].toString() : 'Unknown',
        street: json['s']?.isNotEmpty == true ? json['s'] as String : 'Unknown street',
        city: json['c']?.isNotEmpty == true ? json['c'] as String : 'Unknown city',
        countryCode: json['cc']?.isNotEmpty == true ? json['cc'] as String : '??',
        zipCode: json['z']?.isNotEmpty == true ? json['z'].toString() : '?????',
        location: LatLng((ll[0] as num).toDouble(), (ll[1] as num).toDouble()),
        website: json['w'] as String?,
        isDealer: json['d'] == 1,
      );
    } catch (error, stackTrace) {
      Logger('Garage').severe('Malformed garage', error, stackTrace);
      rethrow;
    }
  }
}
