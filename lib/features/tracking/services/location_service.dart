import 'package:geolocator/geolocator.dart';

class LocationPermissionDenied implements Exception {
  final String message;
  LocationPermissionDenied(this.message);

  @override
  String toString() => message;
}

class LocationService {
  /// Ensures location services are on and permission is granted,
  /// requesting it from the user if needed. Throws [LocationPermissionDenied]
  /// if it can't get access.
  Future<void> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationPermissionDenied(
        'Location services are turned off. Enable them to use live tracking.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationPermissionDenied(
        'Location permission was denied. Grant it to track your ride live.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionDenied(
        'Location permission is permanently denied. Enable it from Settings to use live tracking.',
      );
    }
  }

  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }
}
