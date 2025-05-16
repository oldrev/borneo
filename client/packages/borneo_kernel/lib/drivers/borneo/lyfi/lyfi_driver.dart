import 'dart:convert';
import 'package:borneo_kernel/drivers/borneo/borneo_coap_config.dart';
import 'package:borneo_kernel/drivers/borneo/borneo_probe_coap_config.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:coap/coap.dart';
import 'package:cbor/cbor.dart';

import 'package:borneo_common/exceptions.dart';
import 'package:borneo_common/io/net/coap_client.dart';
import 'package:borneo_common/utils/float.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/metadata.dart';
import 'package:borneo_kernel_abstractions/errors.dart';
import 'package:borneo_kernel_abstractions/models/discovered_device.dart';

import 'package:borneo_kernel_abstractions/models/supported_device_descriptor.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:borneo_kernel_abstractions/idriver.dart';
import 'package:pub_semver/pub_semver.dart';

import '../borneo_device_api.dart';

class LyfiPaths {
  static final Uri info = Uri(path: '/borneo/lyfi/info');
  static final Uri status = Uri(path: '/borneo/lyfi/status');
  static final Uri state = Uri(path: '/borneo/lyfi/state');
  static final Uri color = Uri(path: '/borneo/lyfi/color');
  static final Uri schedule = Uri(path: '/borneo/lyfi/schedule');
  static final Uri mode = Uri(path: '/borneo/lyfi/mode');
  static final Uri correctionMethod =
      Uri(path: '/borneo/lyfi/correction-method');
  static final Uri geoLocation = Uri(path: '/borneo/lyfi/geo-location');
  static final Uri acclimation = Uri(path: '/borneo/lyfi/acclimation');
  static final Uri temporaryDuration =
      Uri(path: '/borneo/lyfi/temporary-duration');

  static final Uri sunSchedule = Uri(path: '/borneo/lyfi/sun/schedule');
  static final Uri sunCurve = Uri(path: '/borneo/lyfi/sun/curve');
}

class LyfiChannelInfo {
  final String name;
  final String color;
  final double brightnessRatio;

  const LyfiChannelInfo({
    required this.name,
    required this.color,
    required this.brightnessRatio,
  });

  factory LyfiChannelInfo.fromMap(dynamic map) {
    return LyfiChannelInfo(
      name: map['name'],
      color: map['color'],
      brightnessRatio: map['brightnessPercent'].toDouble() / 100.0,
    );
  }
}

class LyfiDeviceInfo {
  final bool isStandaloneController;
  final double? nominalPower;
  final int channelCount;
  final List<LyfiChannelInfo> channels;

  const LyfiDeviceInfo({
    required this.isStandaloneController,
    required this.nominalPower,
    required this.channelCount,
    required this.channels,
  });

  factory LyfiDeviceInfo.fromMap(CborMap cborMap) {
    final dynamic map = cborMap.toObject();
    return LyfiDeviceInfo(
        isStandaloneController: map['isStandaloneController'],
        nominalPower: map['nominalPower']?.toDouble(),
        channelCount: map['channelCount'],
        channels: List<LyfiChannelInfo>.from(
          map['channels'].map((x) => LyfiChannelInfo.fromMap(x)),
        ));
  }
}

enum LedState {
  normal,
  dimming,
  temporary,
  preview;

  bool get isLocked => !(this == preview || this == dimming);
}

enum LedRunningMode {
  manual,
  scheduled,
  sun;

  bool get isSchedulerEnabled => this == scheduled;
}

enum LedCorrectionMethod {
  log,
  linear,
  exp,
  gamma,
  cie1931,
}

class GeoLocation {
  final double lat;
  final double lng;
  GeoLocation({required this.lat, required this.lng});

  @override
  String toString() => "(${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})";

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! GeoLocation) {
      return false;
    }
    const double tolerance = 0.00001;
    return (lat - other.lat).abs() < tolerance &&
        (lng - other.lng).abs() < tolerance;
  }

  @override
  int get hashCode => Object.hash(lat, lng);

  factory GeoLocation.fromMap(dynamic map) {
    return GeoLocation(
      lat: map['lat'],
      lng: map['lng'],
    );
  }

  CborMap toCbor() {
    final cborLat = CborFloat(convertToFloat32(lat));
    cborLat.floatPrecision();
    final cborLng = CborFloat(convertToFloat32(lng));
    cborLng.floatPrecision();

    return CborMap({
      CborString("lat"): cborLat,
      CborString("lng"): cborLng,
    });
  }
}

class AcclimationSettings {
  final bool enabled;
  final DateTime startTimestamp;
  final int startPercent;
  final int days;

  AcclimationSettings({
    required this.enabled,
    required this.startTimestamp,
    required this.startPercent,
    required this.days,
  });

  factory AcclimationSettings.fromMap(dynamic map) {
    return AcclimationSettings(
      enabled: map["enabled"],
      startTimestamp:
          DateTime.fromMillisecondsSinceEpoch(map['startTimestamp'] * 1000),
      days: map["days"],
      startPercent: map["startPercent"],
    );
  }

  CborMap toCbor() {
    return CborMap({
      CborString("enabled"): CborBool(enabled),
      CborString("startTimestamp"):
          CborValue((startTimestamp.millisecondsSinceEpoch / 1000.0).round()),
      CborString("startPercent"): CborSmallInt(startPercent),
      CborString("days"): CborSmallInt(days),
    });
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcclimationSettings &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          startTimestamp == other.startTimestamp &&
          startPercent == other.startPercent &&
          days == other.days;

  @override
  int get hashCode =>
      enabled.hashCode ^
      startTimestamp.hashCode ^
      startPercent.hashCode ^
      days.hashCode;
}

class LyfiDeviceStatus {
  final LedState state;
  final LedRunningMode mode;
  final bool unscheduled;
  final Duration temporaryRemaining;
  final int fanPower;
  final List<int> currentColor;
  final List<int> manualColor;
  final List<int> sunColor;
  final bool acclimationEnabled;
  final bool acclimationActivated;

  double get brightness =>
      currentColor.fold(0, (p, v) => p + v).toDouble() *
      100.0 /
      (currentColor.length * 100.0);

  const LyfiDeviceStatus({
    required this.state,
    required this.mode,
    required this.unscheduled,
    required this.temporaryRemaining,
    required this.fanPower,
    required this.currentColor,
    required this.manualColor,
    required this.sunColor,
    this.acclimationEnabled = false,
    this.acclimationActivated = false,
  });

  factory LyfiDeviceStatus.fromMap(CborMap cborMap) {
    final dynamic map = cborMap.toObject();
    return LyfiDeviceStatus(
      state: LedState.values[map['state']],
      mode: LedRunningMode.values[map['mode']],
      unscheduled: map['unscheduled'],
      temporaryRemaining: Duration(seconds: map['tempRemain']),
      fanPower: map['fanPower'],
      currentColor: List<int>.from(map['currentColor']),
      manualColor: List<int>.from(map['manualColor']),
      sunColor: List<int>.from(map['sunColor']),
      acclimationEnabled: map['acclimationEnabled'] ?? false,
      acclimationActivated: map['acclimationActivated'] ?? false,
    );
  }
}

class ScheduledInstant {
  final Duration instant;
  final List<int> color;
  const ScheduledInstant({required this.instant, required this.color});

  factory ScheduledInstant.fromMap(dynamic map) {
    final secs = map['instant'] as int;
    return ScheduledInstant(
      instant: Duration(seconds: secs),
      color: List<int>.from(map['color'], growable: false),
    );
  }

  List<dynamic> toPayload() {
    return [instant.inSeconds, color];
  }

  bool get isZero => !color.any((x) => x != 0);
}

class SunCurveItem {
  final Duration instant;
  final double brightness;
  const SunCurveItem({required this.instant, required this.brightness});

  factory SunCurveItem.fromMap(dynamic map) {
    final secs = map['time'] as double;
    return SunCurveItem(
      instant: Duration(seconds: (secs * 3600.0).round()),
      brightness: map['brightness'],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! SunCurveItem) {
      return false;
    }
    const double tolerance = 0.00001;
    return instant == other.instant &&
        (brightness - other.brightness).abs() < tolerance;
  }

  @override
  int get hashCode => Object.hash(instant, brightness);
}

abstract class ILyfiDeviceApi extends IBorneoDeviceApi {
  LyfiDeviceInfo getLyfiInfo(Device dev);
  Future<LyfiDeviceStatus> getLyfiStatus(Device dev);

  Future<LedState> getState(Device dev);
  Future<void> switchState(Device dev, LedState state);

  Future<LedRunningMode> getMode(Device dev);
  Future<void> switchMode(Device dev, LedRunningMode mode);

  Future<List<ScheduledInstant>> getSchedule(Device dev);
  Future<void> setSchedule(Device dev, Iterable<ScheduledInstant> schedule);

  Future<List<int>> getColor(Device dev);
  Future<void> setColor(Device dev, List<int> color);

  Future<int> getKeepTemp(Device dev);

  Future<LedCorrectionMethod> getCorrectionMethod(Device dev);
  Future<void> setCorrectionMethod(Device dev, LedCorrectionMethod mode);

  Future<Duration> getTemporaryDuration(Device dev);
  Future<void> setTemporaryDuration(Device dev, Duration duration);

  Future<GeoLocation?> getLocation(Device dev);
  Future<void> setLocation(Device dev, GeoLocation location);

  Future<AcclimationSettings> getAcclimation(Device dev);
  Future<void> setAcclimation(Device dev, AcclimationSettings acc);
  Future<void> terminateAcclimation(Device dev);

  Future<List<ScheduledInstant>> getSunSchedule(Device dev);
  Future<List<SunCurveItem>> getSunCurve(Device dev);
}

class LyfiDriverData extends BorneoDriverData {
  int debugCounter = 0;
  final LyfiDeviceInfo _lyfiDeviceInfo;

  LyfiDriverData(super._coap, super._generalDeviceInfo, this._lyfiDeviceInfo);

  LyfiDeviceInfo get lyfiDeviceInfo {
    if (super.isDisposed) {
      ObjectDisposedException(message: 'The object has been disposed.');
    }
    return _lyfiDeviceInfo;
  }
}

class BorneoLyfiDriver
    with BorneoDeviceApiImpl
    implements IDriver, ILyfiDeviceApi {
  static const String lyfiCompatibleString = 'bst,borneo-lyfi';

  @override
  Future<bool> probe(Device dev, {CancellationToken? cancelToken}) async {
    final probeCoapClient =
        CoapClient(dev.address, config: BorneoProbeCoapConfig.coapConfig);
    try {
      // Verify compatible string
      final compatible = await _getCompatible(probeCoapClient);
      if (compatible != lyfiCompatibleString) {
        throw UncompatibleDeviceError(
            "Uncompatible device: `$compatible`", dev);
      }

      // Verify firmware version
      final fwver = await _getFirmwareVersion(probeCoapClient);
      if (!kLyfiFWVersionConstraint.allows(fwver)) {
        throw UnsupportedVersionError(
          'Unsupported firmware version',
          dev,
          currentVersion: fwver,
          versionRange: kLyfiFWVersionConstraint,
        );
      }

      final generalDeviceInfo = await _getGeneralDeviceInfo(probeCoapClient);
      final coapClient =
          CoapClient(dev.address, config: BorneoCoapConfig.coapConfig);
      final lyfiInfo = await _getLyfiInfo(coapClient);
      dev.driverData = LyfiDriverData(coapClient, generalDeviceInfo, lyfiInfo);
      return true;
    } on CoapRequestTimeoutException catch (_) {
      return false;
    } finally {
      probeCoapClient.close();
    }
  }

  @override
  Future<bool> remove(Device dev, {CancellationToken? cancelToken}) async {
    final dd = dev.driverData as LyfiDriverData;
    dd.dispose();
    return true;
  }

  @override
  Future<bool> heartbeat(Device dev, {CancellationToken? cancelToken}) async {
    try {
      await getOnOff(dev).asCancellable(cancelToken); // FIXME
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {}

  Future<String> _getCompatible(CoapClient coap) async {
    final compatible = await coap.getCbor<String>(
      BorneoPaths.compatible,
    );
    return compatible;
  }

  Future<Version> _getFirmwareVersion(CoapClient coap) async {
    final fwver = await coap.getCbor<String>(
      BorneoPaths.firmwareVersion,
    );
    return Version.parse(fwver);
  }

  Future<GeneralBorneoDeviceInfo> _getGeneralDeviceInfo(CoapClient coap) async {
    final response = await coap.get(
      BorneoPaths.deviceInfo,
      accept: CoapMediaType.applicationCbor,
    );
    return GeneralBorneoDeviceInfo.fromMap(
        cbor.decode(response.payload) as CborMap);
  }

  Future<LyfiDeviceInfo> _getLyfiInfo(CoapClient coap) async {
    final response = await coap.get(
      LyfiPaths.info,
      accept: CoapMediaType.applicationCbor,
    );
    return LyfiDeviceInfo.fromMap(cbor.decode(response.payload) as CborMap);
  }

  static SupportedDeviceDescriptor? matches(DiscoveredDevice discovered) {
    if (discovered is MdnsDiscoveredDevice) {
      final compatible = utf8.decode(discovered.txt?['compatible'] ?? [],
          allowMalformed: true);
      if (compatible == lyfiCompatibleString) {
        final matched = SupportedDeviceDescriptor(
          driverDescriptor: borneoLyfiDriverDescriptor,
          address:
              Uri(scheme: 'coap', host: discovered.host, port: discovered.port),
          name:
              utf8.decode(discovered.txt?['name'] ?? [], allowMalformed: true),
          compatible: compatible,
          model: utf8.decode(discovered.txt?['model_name'] ?? [],
              allowMalformed: true),
          fingerprint:
              utf8.decode(discovered.txt?['serno'] ?? [], allowMalformed: true),
          manuf: utf8.decode(discovered.txt?['manuf_name'] ?? [],
              allowMalformed: true),
        );
        return matched;
      }
    }
    return null;
  }

  @override
  Future<int> getKeepTemp(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final response = await dd.coap.get(
      Uri(path: '/borneo/lyfi/thermal/keep-temp'),
      accept: CoapMediaType.applicationCbor,
    );
    return cbor.decode(response.payload).toObject() as int;
  }

  @override
  LyfiDeviceInfo getLyfiInfo(Device dev) {
    final dd = dev.driverData as LyfiDriverData;
    return dd.lyfiDeviceInfo;
  }

  @override
  Future<LyfiDeviceStatus> getLyfiStatus(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    dd.debugCounter += 1;
    final response = await dd.coap.get(
      Uri(path: '/borneo/lyfi/status'),
      accept: CoapMediaType.applicationCbor,
    );
    if (dd.debugCounter >= 3) {
      //throw DeviceBusyError('surprise!', dev);
    }
    return LyfiDeviceStatus.fromMap(cbor.decode(response.payload) as CborMap);
  }

  @override
  Future<List<int>> getColor(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final result = await dd.coap.getCbor<List<Object?>>(LyfiPaths.color);
    return List<int>.from(result, growable: false);
  }

  @override
  Future<void> setColor(Device dev, List<int> color) async {
    final dd = dev.driverData as LyfiDriverData;
    await dd.coap.putCbor(LyfiPaths.color, color);
  }

  @override
  Future<LedState> getState(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final value = await dd.coap.getCbor<int>(LyfiPaths.state);
    return LedState.values[value];
  }

  @override
  Future<void> switchState(Device dev, LedState state) async {
    final dd = dev.driverData as LyfiDriverData;
    await dd.coap.putCbor(LyfiPaths.state, state.index);
  }

  @override
  Future<LedRunningMode> getMode(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final value = await dd.coap.getCbor<int>(LyfiPaths.mode);
    return LedRunningMode.values[value];
  }

  @override
  Future<void> switchMode(Device dev, LedRunningMode mode) async {
    final dd = dev.driverData as LyfiDriverData;
    return await dd.coap.putCbor(LyfiPaths.mode, mode.index);
  }

  @override
  Future<List<ScheduledInstant>> getSchedule(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final items = await dd.coap.getCbor<List<dynamic>>(LyfiPaths.schedule);
    return items.map((x) => ScheduledInstant.fromMap(x!)).toList();
  }

  @override
  Future<void> setSchedule(
      Device dev, Iterable<ScheduledInstant> schedule) async {
    final dd = dev.driverData as LyfiDriverData;
    final payload = schedule.map((x) => x.toPayload());
    return await dd.coap.putCbor(LyfiPaths.schedule, payload);
  }

  @override
  Future<LedCorrectionMethod> getCorrectionMethod(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final value = await dd.coap.getCbor<int>(LyfiPaths.correctionMethod);
    return LedCorrectionMethod.values[value];
  }

  @override
  Future<void> setCorrectionMethod(
      Device dev, LedCorrectionMethod correctionMethod) async {
    final dd = dev.driverData as LyfiDriverData;
    return await dd.coap
        .putCbor(LyfiPaths.correctionMethod, correctionMethod.index);
  }

  @override
  Future<Duration> getTemporaryDuration(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final minutes = await dd.coap.getCbor<int>(LyfiPaths.temporaryDuration);
    return Duration(minutes: minutes);
  }

  @override
  Future<void> setTemporaryDuration(Device dev, Duration duration) async {
    final dd = dev.driverData as LyfiDriverData;
    final minutes = duration.inMinutes;
    return await dd.coap.putCbor(LyfiPaths.temporaryDuration, minutes);
  }

  @override
  Future<GeoLocation?> getLocation(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final result = await dd.coap.getCbor<dynamic>(LyfiPaths.geoLocation);
    if (result != null) {
      return GeoLocation.fromMap(result);
    } else {
      return null;
    }
  }

  @override
  Future<void> setLocation(Device dev, GeoLocation location) async {
    final dd = dev.driverData as LyfiDriverData;
    return await dd.coap.putCbor(LyfiPaths.geoLocation, location);
  }

  @override
  Future<AcclimationSettings> getAcclimation(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final map = await dd.coap.getCbor<dynamic>(LyfiPaths.acclimation);
    return AcclimationSettings.fromMap(map);
  }

  @override
  Future<void> setAcclimation(Device dev, AcclimationSettings acc) async {
    final dd = dev.driverData as LyfiDriverData;
    return await dd.coap.postCbor(LyfiPaths.acclimation, acc);
  }

  @override
  Future<void> terminateAcclimation(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    await dd.coap.delete(LyfiPaths.acclimation);
  }

  @override
  Future<List<ScheduledInstant>> getSunSchedule(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final items = await dd.coap.getCbor<List<dynamic>>(LyfiPaths.sunSchedule);
    return items.map((x) => ScheduledInstant.fromMap(x!)).toList();
  }

  @override
  Future<List<SunCurveItem>> getSunCurve(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final items = await dd.coap.getCbor<List<dynamic>>(LyfiPaths.sunCurve);
    return items.map((x) => SunCurveItem.fromMap(x!)).toList();
  }
}
