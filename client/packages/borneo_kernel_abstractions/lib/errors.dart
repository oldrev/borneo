import 'dart:io';
import 'package:pub_semver/pub_semver.dart';

import 'package:borneo_kernel_abstractions/device.dart';

class DeviceError extends IOException {
  final String message;
  final Device device;
  DeviceError(this.message, this.device);
}

class UnsupportedVersionError extends DeviceError {
  final Version currentVersion;
  final VersionConstraint? versionRange;

  UnsupportedVersionError(
    super.message,
    super.device, {
    required this.currentVersion,
    required this.versionRange,
  });

  @override
  String toString() {
    var result = 'UnsupportedVersionError: $message';
    result += '\nCurrent Version: $currentVersion';
    result += '\nSupported Version: $versionRange';
    return result;
  }
}

class DeviceBusyError extends DeviceError {
  DeviceBusyError(
    super.message,
    super.device,
  );

  @override
  String toString() {
    var result = 'DeviceBusyError: $message';
    result += '\nDevice: ${device.address}';
    return result;
  }
}

class DeviceNotFoundError extends DeviceError {
  DeviceNotFoundError(
    super.message,
    super.device,
  );

  @override
  String toString() {
    var result = 'DeviceNotFoundError: $message';
    result += '\nDevice: ${device.address}';
    return result;
  }
}