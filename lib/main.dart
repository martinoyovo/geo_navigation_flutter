import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:flutter/material.dart';
import 'package:navigation_demo/navigation_app_simulated.dart';

void main() {
  ArcGISEnvironment.apiKey = const String.fromEnvironment('API_KEY');
  ArcGISEnvironment.setLicenseUsingKey(
    const String.fromEnvironment('STANDARD_LICENSE'),
  );
  runApp(const MyApp());martinoyovo/geo_navigation_flutter


}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigation Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan),
        useMaterial3: true,
        iconTheme: IconThemeData(
          color: Colors.black87
        )
      ),
      home: const NavigationAppSimulated(),
    );
  }
}