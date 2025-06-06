import 'dart:async';

import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class NavigationAppSimulated extends StatefulWidget {
  const NavigationAppSimulated({super.key});

  @override
  State<NavigationAppSimulated> createState() => _NavigationAppSimulatedState();
}

class _NavigationAppSimulatedState extends State<NavigationAppSimulated> {
  final _mapViewController = ArcGISMapView.createController();

  // setup location
  final _locationDataSource = SimulatedLocationDataSource();
  // setup route
  ArcGISRoute? _route;
  late RouteTracker _routeTracker;
  late RouteResult _routeResult;

  // This class holds the data for a single navigation step (maneuver) in a route, like a turn, roundabout exit, or arrival.
  final _directionsList = <DirectionManeuver>[];
  final _initialLocation = ArcGISPoint(
    x: -1.2163758893108882,
    y: 54.16376654622336,
    spatialReference: SpatialReference.wgs84,
  );
  final _nextDeliveryLocation = ArcGISPoint(
    x: -0.655327,
    y: 54.477301,
    spatialReference: SpatialReference.wgs84,
  );

  // display route
  final _routeGraphicsOverlay = GraphicsOverlay();
  late Graphic _remainingRouteGraphic;
  var _distance = '0';
  var _travelTime = '0';

  // navigation configuration
  RouteTrackerLocationDataSource? _routeTrackerLocationSource;
  late FlutterTts _ttsEngine;
  StreamSubscription<VoiceGuidance>? _voiceGuidanceSubscription;
  StreamSubscription<TrackingStatus>? _trackingStatusSubscription;
  final _directionsTextNotifier = ValueNotifier('Directions placeholder');

  // geotriggers
  FeatureTable? _warningPointsTable;
  late FeatureLayer _pointFeatureLayer;
  late FeatureLayer _bufferFeatureLayer;
  StreamSubscription? _geoTriggerSubscription;
  var _warningType = '';

  // UI flags
  var _isNavigating = false;
  var _warningActive = false;
  var _speechEngineReady = true;
  var _isMuted = false;
  var _showPreview = false;

  @override
  void initState() {
    _ttsEngine = FlutterTts()..setSpeechRate(0.5);
    initAudioCategory();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: Expanded(
              child: Stack(
                children: [
                  ArcGISMapView(
                    controllerProvider: () => _mapViewController,
                    onMapViewReady: onMapViewReady,
                  ),
                  SafeArea(
                    minimum: EdgeInsets.all(15),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 10,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Visibility(
                          visible: _isNavigating,
                          child: buildDirectionsWidget(),
                        ),
                        Visibility(
                          visible: _warningActive,
                          child: buildWarningWidget(),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 20,
                    bottom: MediaQuery.of(context).size.height * 0.25,
                    child: iconButtons(),
                  ),
                  Visibility(
                    visible: _showPreview,
                    child: buildPreviewWidget(),
                  ),
                ],
              ),
            ),
          ),
          buildNavigationControls(),
        ],
      ),
    );
  }

  Future<void> initAudioCategory() async {
    await _ttsEngine.setIosAudioCategory(IosTextToSpeechAudioCategory.ambient, [
      IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
      IosTextToSpeechAudioCategoryOptions.mixWithOthers,
    ], IosTextToSpeechAudioMode.voicePrompt);
  }

  void onMapViewReady() async {
    final map = ArcGISMap.withBasemapStyle(BasemapStyle.arcGISNavigation);
    _mapViewController.arcGISMap = map;
    _mapViewController.setViewpoint(
      Viewpoint.fromCenter(_initialLocation, scale: 50000),
    );
    await initStaticLocation();
    await loadFeatureLayers();
    await configureGeotriggerMonitor();
    await initRoute();
  }

  // Configure Route

  Future<void> initRoute() async {
    final initialLocation = Stop(_initialLocation);
    final nextDeliveryLocation = Stop(_nextDeliveryLocation);

    // Create a route task from a routing service.
    final routeTask = RouteTask.withUri(
      Uri.parse(
        'https://route-api.arcgis.com/arcgis/rest/services/World/Route/NAServer/Route_World',
      ),
    );

    // Configure route parameters.
    final routeParameters = await routeTask.createDefaultParameters();
    routeParameters.setStops([initialLocation, nextDeliveryLocation]);
    routeParameters.findBestSequence = true;
    routeParameters.preserveFirstStop = true;
    routeParameters.returnRoutes = true;
    routeParameters.returnStops = true;
    routeParameters.returnDirections = true;

    // Solve the route and get the route from the route result.
    _routeResult = await routeTask.solveRoute(routeParameters);
    if (_routeResult.routes.isEmpty) return;
    final route = _routeResult.routes.first;
    final distance = formatDistance(route);
    final travelTime = formatTime(route.travelTime);
    setState(() {
      _route = route;
      _directionsList.addAll(route.directionManeuvers);
      _distance = '$distance mi';
      _travelTime = travelTime;
    });
  }

  // Configure Navigation

  Future<void> startNavigation() async {
    setState(() {
      _isNavigating = true;
      _directionsTextNotifier.value = 'Starting navigation...';
    });
    configureSimulatedLocation();

    // Init a route tracker and assign a route result.
    _routeTracker =
        RouteTracker.create(
          routeResult: _routeResult,
          routeIndex: 0,
          skipCoincidentStops: true,
        )!;
    _routeTracker.voiceGuidanceUnitSystem = UnitSystem.imperial;

    // Listen to tracking status and update graphics and directions.
    _trackingStatusSubscription = _routeTracker.onTrackingStatusChanged.listen((
      status,
    ) async {
      // Update the route graphic to only display the remaining route geometry.
      _remainingRouteGraphic.geometry = status.routeProgress.remainingGeometry;

      if (status.destinationStatus == DestinationStatus.notReached) {
        // If the destination is not reached display the next direction in the UI.
        _directionsTextNotifier.value =
            _directionsList[status.currentManeuverIndex + 1].directionText;
      } else if (status.destinationStatus == DestinationStatus.reached) {
        stopTTS();
      }
    });

    // Listen to voice guidance updates and feed to text-to-speech engine.
    _routeTracker.setSpeechEngineReady(() => _speechEngineReady);
    _voiceGuidanceSubscription = _routeTracker.onNewVoiceGuidance.listen((
      voiceGuidance,
    ) {
      updateVoiceGuidance(voiceGuidance.text);
    });

    // Configure a route tracker location data source.
    _routeTrackerLocationSource = RouteTrackerLocationDataSource(
      routeTracker: _routeTracker,
      locationDataSource: _locationDataSource,
    );
    _mapViewController.locationDisplay.dataSource =
        _routeTrackerLocationSource!;
    _mapViewController.locationDisplay.autoPanMode =
        LocationDisplayAutoPanMode.navigation;
    // Start the route tracker.
    _routeTrackerLocationSource!.start();
  }

  void updateVoiceGuidance(String voiceGuidance) async {
    _speechEngineReady = false;
    await _ttsEngine.speak(voiceGuidance);
    _speechEngineReady = true;
  }

  // Configure Geotriggers

  Future<void> configureGeotriggerMonitor() async {
    // Create feature fence parameters using feature table and set a buffer.
    final fenceParameters = FeatureFenceParameters(
      featureTable: _warningPointsTable!,
      bufferDistance: 150,
    );

    // Create a geotrigger feed using the active location data source.
    final geotriggerFeed = LocationGeotriggerFeed(
      locationDataSource: _locationDataSource,
    );

    // Create a fence geotrigger with desired rule and message.
    final geotrigger = FenceGeotrigger(
      feed: geotriggerFeed,
      ruleType: FenceRuleType.enterOrExit,
      fenceParameters: fenceParameters,
      messageExpression: ArcadeExpression(
        expression: r'$fencefeature.warning_type',
      ),
    );

    // Create a geotrigger monitor, subscribe to events and start.
    final monitor = GeotriggerMonitor(geotrigger);
    _geoTriggerSubscription = monitor.onGeotriggerNotificationEvent.listen(
      handleGeotriggerEvent,
    );
    await monitor.start();
  }

  // Handle response to geotrigger notifications.
  void handleGeotriggerEvent(GeotriggerNotificationInfo info) {
    final fenceInfo = info as FenceGeotriggerNotificationInfo;

    setState(() {
      switch (fenceInfo.fenceNotificationType) {
        case FenceNotificationType.entered:
          // On enter...
          // Display warning
          _warningActive = true;
          _warningType = fenceInfo.message;
          // Send desired voice guidance to text-to-speech engine.
          updateVoiceGuidance('Warning, $_warningType, be aware.');
        case FenceNotificationType.exited:
          // On exit...
          // Hide warning
          _warningActive = false;
          // Send desired voice guidance to text-to-speech engine.
          updateVoiceGuidance('End of $_warningType');
      }
    });
  }

  Future<void> loadFeatureLayers() async {
    final portal = Portal.arcGISOnline();
    // Safety zones
    final item = PortalItem.withPortalAndItemId(
      portal: portal,
      itemId: '49e3861dd16d4b4abdadbb1acbf26bd8',
    );
    // Buffer
    final bufferItem = PortalItem.withPortalAndItemId(
      portal: portal,
      itemId: 'ad36192fc08340cb877d31593e3ef204',
    );
    _pointFeatureLayer = FeatureLayer.withFeatureLayerItem(item);
    _bufferFeatureLayer = FeatureLayer.withFeatureLayerItem(bufferItem);
    await _pointFeatureLayer.load();
    await _bufferFeatureLayer.load();
    _pointFeatureLayer.isVisible = false;
    _bufferFeatureLayer.isVisible = false;
    _warningPointsTable = _pointFeatureLayer.featureTable;
    _mapViewController.arcGISMap!.operationalLayers.addAll([
      _bufferFeatureLayer,
      _pointFeatureLayer,
    ]);
  }

  void displayRoutePreview(Polyline routeGeometry) {
    _mapViewController.graphicsOverlays.clear();
    setState(() {
      _showPreview = !_showPreview;
    });
    final baseLineSymbol = SimpleLineSymbol(
      color: Colors.deepPurple,
      width: 10,
    );
    final topLineSymbol = SimpleLineSymbol(
      color: Colors.deepPurpleAccent,
      width: 3,
    );
    _remainingRouteGraphic = Graphic(
      geometry: routeGeometry,
      symbol: CompositeSymbol(symbols: [baseLineSymbol, topLineSymbol]),
    );
    final baseSymbol = SimpleMarkerSymbol(color: Colors.deepPurple, size: 20);
    final topSymbol = SimpleMarkerSymbol(color: Color(0xFFF3F3F3), size: 10);
    final compSymbol = CompositeSymbol(symbols: [baseSymbol, topSymbol]);
    final destinationGraphic = Graphic(
      geometry: _nextDeliveryLocation,
      symbol: compSymbol,
    )..zIndex = 100;
    _routeGraphicsOverlay.graphics.addAll([
      _remainingRouteGraphic,
      destinationGraphic,
    ]);
    _mapViewController.graphicsOverlays.add(_routeGraphicsOverlay);
    _mapViewController.setViewpointGeometry(
      routeGeometry.extent,
      paddingInDiPs: 50.0,
    );
  }

  void configureSimulatedLocation() {
    _locationDataSource.setLocationsWithPolyline(
      _route!.routeGeometry!,
      simulationParameters: SimulationParameters(
        startTime: DateTime.now(),
        speed: 19,
      ),
    );
  }

  void stopTTS() {
    // If the destination is reached stop the location, stop the navigation.
    _ttsEngine.stop();
    _directionsTextNotifier.value = 'You have reached the drop off location.';
    setState(() => _isNavigating = false);
  }

  void zoomToLocation() {
    setState(() {
      _showPreview = false;
    });
    _mapViewController.locationDisplay.autoPanMode =
        LocationDisplayAutoPanMode.recenter;
    _isNavigating
        ? _mapViewController.locationDisplay.autoPanMode =
            LocationDisplayAutoPanMode.navigation
        : _mapViewController.locationDisplay.autoPanMode =
            LocationDisplayAutoPanMode.recenter;
  }

  void showWarnings() {
    _bufferFeatureLayer.isVisible = !_bufferFeatureLayer.isVisible;
    _pointFeatureLayer.isVisible = !_pointFeatureLayer.isVisible;
  }

  Future<void> muteVoiceGuidance() async {
    if (_isMuted) {
      await _ttsEngine.setVolume(1);
      setState(() {
        _isMuted = false;
      });
    } else {
      await _ttsEngine.setVolume(0);
      setState(() {
        _isMuted = true;
      });
    }
  }

  String formatDistance(ArcGISRoute route) {
    return (route.totalLength * 0.00062137).toStringAsFixed(2);
  }

  String formatTime(double time) {
    final int hour = time ~/ 60;
    final int minutes = (time % 60).round();
    return '$hour hr $minutes m';
  }

  Future<void> stopNavigation() async {
    _routeTrackerLocationSource!.stop();
    _mapViewController.graphicsOverlays.clear();
    setState(() {
      _isNavigating = false;
      _showPreview = false;
    });
  }

  Widget buildPreviewWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).primaryColorLight.withValues(alpha: 0.9),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 1.5,
                  ),
                  right: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 1.5,
                  ),
                ),
              ),
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    children: [
                      Text(
                        'Route Preview',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 30,
                        children: [
                          Text(
                            _distance,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          Text(
                            _travelTime,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget buildWarningWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            color: Colors.amberAccent.shade100,
            border: Border.all(color: Colors.orange, width: 5),
          ),
          child: Column(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              Text(
                _warningType.isEmpty ? 'Warning' : _warningType,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildDirectionsWidget() {
    return ValueListenableBuilder(
      valueListenable: _directionsTextNotifier,
      builder: (context, statusText, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(context).primaryColor,
          ),
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              getDirectionIcon(statusText),
              Flexible(
                child: Text(
                  style: TextStyle(
                    color: Theme.of(context).primaryColorLight,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  statusText,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget iconButtons() {
    return Column(
      spacing: 15,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          tooltip: 'Toggle voice guidance',
          backgroundColor: Theme.of(context).primaryColor,
          shape: StadiumBorder(),
          elevation: 0,
          onPressed: muteVoiceGuidance,
          child: Icon(
            _isMuted ? Icons.volume_off_rounded : Icons.volume_up,
            color: Colors.white,
          ),
        ),
        FloatingActionButton(
          tooltip: 'Zoom to location',
          backgroundColor: Theme.of(context).primaryColor,
          shape: StadiumBorder(),
          elevation: 0,
          onPressed: zoomToLocation,
          child: Icon(Icons.my_location_rounded, color: Colors.white),
        ),
        FloatingActionButton(
          tooltip: 'View warnings',
          backgroundColor: Theme.of(context).primaryColor,
          shape: StadiumBorder(),
          elevation: 0,
          onPressed: showWarnings,
          child: Icon(Icons.warning_rounded, color: Colors.white),
        ),
      ],
    );
  }

  Widget buildNavigationControls() {
    return Container(
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 30),
      decoration: BoxDecoration(color: Theme.of(context).primaryColor),
      child: SizedBox(
        height: 50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () async {
                await initRoute();
                await Future.delayed(const Duration(milliseconds: 200));
                if (_route?.routeGeometry != null) {
                  displayRoutePreview(_route!.routeGeometry!);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_rounded, color: Colors.black87),
                  Text(
                    'Directions',
                    style: TextStyle(fontSize: 18, color: Colors.black87),
                  ),
                ],
              ),
            ),
            FloatingActionButton(
              mini: true,
              elevation: 0,
              backgroundColor: Colors.white,
              shape: StadiumBorder(),
              onPressed: () async {
                if (_distance == '0') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Please get directions first before starting the navigation.",
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                _isNavigating
                    ? await stopNavigation()
                    : await startNavigation();
              },
              child: Icon(
                _isNavigating ? Icons.stop_rounded : Icons.navigation_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget getDirectionIcon(String statusText) {
    if (statusText.contains('forward')) {
      return Padding(
        padding: const EdgeInsets.all(5.0),
        child: Icon(Icons.straight, color: Colors.white, size: 50),
      );
    } else if (statusText.contains('right')) {
      return Padding(
        padding: const EdgeInsets.all(5.0),
        child: Icon(Icons.turn_right, color: Colors.white, size: 50),
      );
    } else if (statusText.contains('left')) {
      return Padding(
        padding: const EdgeInsets.all(5.0),
        child: Icon(Icons.turn_left, color: Colors.white, size: 50),
      );
    }
    return Icon(Icons.straight, color: Colors.white, size: 50);
  }

  Future<void> initStaticLocation() async {
    final json = await rootBundle.loadString('assets/simulated_location.json');
    final polyline = Geometry.fromJsonString(json) as Polyline;
    _locationDataSource.setLocationsWithPolyline(polyline);
    _mapViewController.locationDisplay.dataSource = _locationDataSource;
    await _locationDataSource.start();
  }

  @override
  void dispose() {
    _locationDataSource.stop();
    _routeTrackerLocationSource!.stop();
    if (_geoTriggerSubscription != null) {
      _geoTriggerSubscription!.cancel();
    }
    _ttsEngine.stop();
    _voiceGuidanceSubscription?.cancel();
    _trackingStatusSubscription?.cancel();

    super.dispose();
  }
}
