import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/log_helper.dart';
import '../helper_widgets/header.dart';

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
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new_rounded, size: 20),
      onTap: () => _open(url),
    );
  }

  Widget _tileGroup(List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const Divider(),
            children[index],
          ],
        ],
      ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
              child: Text(
                FlutterI18n.translate(context, 'support_intro'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
            ),
            Header(FlutterI18n.translate(context, 'support_guides')),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: FaqWidget(),
            ),
            Header(FlutterI18n.translate(context, 'support_community')),
            _tileGroup([
              _linkTile(
                icon: Icons.discord_outlined,
                title: FlutterI18n.translate(context, 'support_discord'),
                subtitle: FlutterI18n.translate(context, 'support_discord_description'),
                url: _discordUrl,
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(FlutterI18n.translate(context, 'settings_report')),
                subtitle: Text(FlutterI18n.translate(context, 'support_report_description')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => LogHelper.startBugReport(context),
              ),
              _linkTile(
                icon: Icons.data_object_rounded,
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
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(FlutterI18n.translate(context, 'support_faq_load_error')),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            child: SizedBox(height: 96, child: Center(child: CircularProgressIndicator())),
          );
        }

        final faq = snapshot.data!;
        return Column(
          children: [
            for (final entry in faq.entries.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: Icon(_categoryIcon(entry.$1)),
                    title: Text(entry.$2.key),
                    children: [
                      for (final question in (entry.$2.value as Map<String, dynamic>).entries) ...[
                        const Divider(),
                        ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          collapsedBackgroundColor: Theme.of(context).colorScheme.surface,
                          title: Text(question.key),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                question.value.toString(),
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      height: 1.5,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
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
        .get(Uri.parse('https://reunu.github.io/unustasis-data/garages.json'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      Logger('GarageWidget').severe('Failed to load garages', response.toString());
      throw Exception('Failed to load garages');
    }
    final garages = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return garages.map((garage) => Garage.fromJson(garage as Map<String, dynamic>)).toList();
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
    final result = await Future.wait([_getGarages(), _getPosition()]);
    final garages = result[0] as List<Garage>;
    final position = result[1] as Position;
    for (final garage in garages) {
      garage.distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        garage.location.latitude,
        garage.location.longitude,
      );
    }
    garages.sort((a, b) => a.distance!.compareTo(b.distance!));
    return garages.take(5).toList();
  }

  void _load() => setState(() => _garages = _getClosestGarages());

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
              Text(
                FlutterI18n.translate(context, 'support_garages_find_description'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    FlutterI18n.translate(context, 'support_garages_none'),
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
        return SizedBox(
          height: 208,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: snapshot.data!.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _GarageTile(garage: snapshot.data![index]),
          ),
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
    return SizedBox(
      width: 300,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(garage.name,
                  style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text('${garage.street}, ${garage.city}', maxLines: 2, overflow: TextOverflow.ellipsis),
              const Spacer(),
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
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => MapsLauncher.launchQuery('${garage.name} ${garage.street}, ${garage.zipCode}'),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(FlutterI18n.translate(context, 'support_garage_map')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          garage.phone == 'Unknown' ? null : () => launchUrl(Uri(scheme: 'tel', path: garage.phone)),
                      icon: const Icon(Icons.phone_outlined),
                      label: Text(FlutterI18n.translate(context, 'support_garage_call')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
    required this.country,
    required this.countryCode,
    required this.zipCode,
    required this.location,
  });

  String name;
  String phone;
  String street;
  String city;
  String country;
  String countryCode;
  String zipCode;
  LatLng location;
  double? distance;

  factory Garage.fromJson(Map<String, dynamic> json) {
    try {
      return Garage(
        name: json['name']?.isNotEmpty == true ? json['name'] as String : 'Unnamed',
        phone: json['Phone']?.isNotEmpty == true ? json['Phone'].toString() : 'Unknown',
        street: json['ShippingStreet']?.isNotEmpty == true ? json['ShippingStreet'] as String : 'Unknown street',
        city: json['ShippingCity']?.isNotEmpty == true ? json['ShippingCity'] as String : 'Unknown city',
        country: json['ShippingCountry']?.isNotEmpty == true ? json['ShippingCountry'] as String : 'Unknown country',
        countryCode: json['ShippingCountryCode']?.isNotEmpty == true ? json['ShippingCountryCode'] as String : '??',
        zipCode: json['ShippingPostalCode']?.isNotEmpty == true ? json['ShippingPostalCode'].toString() : '?????',
        location: LatLng(
          double.parse(json['ShippingLatitude']?.isNotEmpty == true ? json['ShippingLatitude'] as String : '0'),
          double.parse(json['ShippingLongitude']?.isNotEmpty == true ? json['ShippingLongitude'] as String : '0'),
        ),
      );
    } catch (error, stackTrace) {
      Logger('Garage').severe('Malformed garage', error, stackTrace);
      rethrow;
    }
  }
}
