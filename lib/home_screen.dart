import 'dart:async';
import 'dart:io';

import 'package:activity_recognition_flutter/activity_recognition_flutter.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;

import 'network/gql_client.dart';
import 'network/gql_document.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _kLocationServicesDisabledMessage = 'Location services are disabled.';
  static const String _kPermissionDeniedMessage = 'Location permission denied.';
  static const String _kPermissionDeniedForeverMessage = 'Location permission denied forever.';
  static const String _kPermissionGrantedMessage = 'Location permission granted.';
  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;


  static const String _micPermissionDeniedMessage = 'Mic permission denied.';
  static const String _micPermissionGrantedMessage = 'Mic permission granted.';
  StreamSubscription<NoiseReading>? _noiseStreamSubscription;
  final NoiseMeter _noiseMeter  = NoiseMeter();

  StreamSubscription<ActivityEvent>? activityStreamSubscription;
  final ActivityRecognition activityRecognition = ActivityRecognition();

  String locationMessage = "";
  String noiseMessage = "";
  String activityMessage = "";
  late ActivityEvent activityEvent;
  GraphQLClient? _graphQLClient;
  Position? currentPosition;
  NoiseReading? currentNoiseReading;


  @override
  void initState() {
    _init();
    super.initState();
  }

  void _init() async{
    _locationServiceStatusStream();
    _startActivityRecognition();
    Timer.periodic(const Duration(seconds:10), (Timer t) => logData());
  }
  
  void logData(){
    if(currentPosition != null && currentNoiseReading != null){
      _graphQLClient?.mutate(MutationOptions(
        document: gql(insertLocationNoise),
        variables: {'longitude': currentPosition!.longitude ,
          "latitude": currentPosition!.latitude ,
          "noise": currentNoiseReading!.meanDecibel},
        onError: (error){
          print(error);
        },
        onCompleted: (dynamic resultData) {
          print(resultData);
        },
      ));
    }
  }

  
  void _startActivityRecognition() async {
    activityEvent = ActivityEvent(ActivityType.UNKNOWN, 0);
    if (Platform.isAndroid) {
      if (await permission_handler.Permission.activityRecognition.request().isDenied) {
         return;
      }
    }
    await _handleLocationPermission();
    if(await permission_handler.Permission.microphone.request().isGranted){
        setState(()=> noiseMessage = _micPermissionGrantedMessage);
    }else{
        setState(()=> noiseMessage = _micPermissionDeniedMessage);
    }

    activityStreamSubscription = activityRecognition
        .activityStream(runForegroundService: true)
        .handleError((error) {
            activityStreamSubscription?.cancel();
            activityStreamSubscription = null;
            _positionStreamSubscription?.cancel();
            _positionStreamSubscription = null;
            _noiseStreamSubscription?.cancel();
            _noiseStreamSubscription = null;
            setState(() {
              activityEvent = ActivityEvent(ActivityType.UNKNOWN, 0);
              activityMessage = "Activity streaming error: ${error.toString()}";
            });
        }).listen((activity){
            print(activity.toString());
            final listen = activity.type == ActivityType.ON_FOOT;
            _locationListening(listen);
            _noiseListening(listen);
            setState(() { activityEvent = activity;});
        });

  }

  @override
  Widget build(BuildContext context) {
    const verticalSpace = SizedBox(height: 50,);
    return Scaffold(
      appBar: AppBar(actions: [_createActions()],),
      body: Center(
        child: FutureBuilder<GraphQLClient>(
          future: gqlClient,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
               return Text(snapshot.error.toString());
            } else if (snapshot.hasData) {
                _graphQLClient = snapshot.data!;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _activityIcon(activityEvent.type),
                        Text(activityEvent.typeString)
                      ],
                    ),
                    verticalSpace,
                    if(activityMessage.isNotEmpty)
                      Text(activityMessage),
                    verticalSpace,
                    Text(locationMessage),
                    verticalSpace,
                    Text(noiseMessage),
                  ],
                );
            }
            return const CircularProgressIndicator();
          }
        ),
      ),
    );
  }

  Icon _activityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.WALKING:
        return const Icon(Icons.directions_walk);
      case ActivityType.IN_VEHICLE:
        return const Icon(Icons.car_rental);
      case ActivityType.ON_BICYCLE:
        return const Icon(Icons.pedal_bike);
      case ActivityType.ON_FOOT:
        return const Icon(Icons.directions_walk);
      case ActivityType.RUNNING:
        return const Icon(Icons.run_circle);
      case ActivityType.STILL:
        return const Icon(Icons.cancel_outlined);
      case ActivityType.TILTING:
        return const Icon(Icons.redo);
      default:
        return const Icon(Icons.device_unknown);
    }
  }

  PopupMenuButton _createActions() {
    return PopupMenuButton(
      elevation: 40,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text("Settings", style: TextStyle(fontSize: 18),)),
      ),
      onSelected: (value) async {
        switch (value) {
          case 1:
            _openAppSettings();
            break;
          case 2:
            _openLocationSettings();
            break;
          default:
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          child: Text("Open App Settings"),
          value: 1,
        ),
        if (Platform.isAndroid)
          const PopupMenuItem(
            child: Text("Open Location Settings"),
            value: 2,
          ),
      ],
    );
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await _geolocatorPlatform.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() { locationMessage = _kLocationServicesDisabledMessage;});
      return false;
    }

    permission = await _geolocatorPlatform.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocatorPlatform.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() { locationMessage = _kPermissionDeniedMessage;});
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() { locationMessage = _kPermissionDeniedForeverMessage;});
      return false;
    }

    setState(() { locationMessage = _kPermissionGrantedMessage;});
    return true;

  }

  void _locationServiceStatusStream() {
    if (_serviceStatusStreamSubscription == null) {
      final serviceStatusStream = _geolocatorPlatform.getServiceStatusStream();
      _serviceStatusStreamSubscription = serviceStatusStream.handleError((error) {
              _serviceStatusStreamSubscription?.cancel();
              _serviceStatusStreamSubscription = null;
          }).listen((serviceStatus) {
              String serviceStatusValue;
              if (serviceStatus == ServiceStatus.enabled) {
                serviceStatusValue = 'enabled';
              } else {
                stopLocationListening();
                serviceStatusValue = 'disabled';
              }
               setState(() {
                 locationMessage = 'Location service has been $serviceStatusValue';
               });
          });
    }
  }

  void _openLocationSettings() async {
    final opened = await _geolocatorPlatform.openLocationSettings();
    if (opened) {
      locationMessage = 'Location Settings Opened';
    } else {
      locationMessage = 'Error opening Location Settings';
    }
    setState(() {});
  }

  void _openAppSettings() async {
    final opened = await _geolocatorPlatform.openAppSettings();
    if (opened) {
      locationMessage = 'Application Settings Opened.';
    } else {
      locationMessage = 'Error opening Application Settings.';
    }
  }

  void _locationListening(bool listen) {
    if (_positionStreamSubscription == null) {
      final positionStream = _geolocatorPlatform.getPositionStream();
      _positionStreamSubscription = positionStream.handleError((error) {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
        currentPosition = null;
        setState(() {
          locationMessage = "Location streaming error: ${error.toString()}";
        });
      }).listen((position){
          currentPosition = position;
          setState(() { locationMessage = position.toString();});
      });
      _positionStreamSubscription?.pause();
    }

    setState(() {
      if (_positionStreamSubscription == null) return;

      if (listen && _positionStreamSubscription!.isPaused) {
        _positionStreamSubscription!.resume();
        locationMessage = 'Location streaming resumed';
      } else if(!_positionStreamSubscription!.isPaused) {
        _positionStreamSubscription!.pause();
        locationMessage = 'Location streaming paused';
        currentPosition = null;
      }
    });
  }

  void _noiseListening(bool listen) {
    if (_noiseStreamSubscription == null) {
      _noiseStreamSubscription = _noiseMeter.noiseStream.handleError((error) {
        _noiseStreamSubscription?.cancel();
        _noiseStreamSubscription = null;
        currentNoiseReading = null;
        setState(() {
          noiseMessage = "Noise streaming error: ${error.toString()}";
        });
      }).listen((noiseReading){
        currentNoiseReading = noiseReading;
        setState(() { noiseMessage = "Noise Decibel: ${noiseReading.meanDecibel.toString()}";});
      }

      );
      _noiseStreamSubscription?.pause();
    }

    setState(() {
      if (_noiseStreamSubscription == null) return;

      if (listen && _noiseStreamSubscription!.isPaused) {
        _noiseStreamSubscription!.resume();
        noiseMessage = 'Noise streaming resumed';
      } else if(!_noiseStreamSubscription!.isPaused) {
        _noiseStreamSubscription!.pause();
        noiseMessage = 'Noise streaming paused';
        currentNoiseReading = null;
      }
    });
  }

  void stopNoiseListening() async {
    try {
      _noiseStreamSubscription?.cancel();
      _noiseStreamSubscription = null;
    } catch (error) {
      print('stopNoiseListening error: $error');
    }
  }

  void stopLocationListening() async {
    try {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
    } catch (error) {
      print('stopLocationListening error: $error');
    }
  }

  void stopActivityListening() async {
    try {
      activityStreamSubscription?.cancel();
      activityStreamSubscription = null;
    } catch (error) {
      print('stopLocationListening error: $error');
    }
  }

  @override
  void dispose() {
    stopActivityListening();
    stopLocationListening();
    stopNoiseListening();
    super.dispose();
  }

}
