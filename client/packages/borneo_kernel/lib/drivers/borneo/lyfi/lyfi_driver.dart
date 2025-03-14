import 'dart:convert';
import 'package:coap/coap.dart';
import 'package:cbor/cbor.dart';

import 'package:borneo_common/exceptions.dart';
import 'package:borneo_common/io/net/coap_client.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/metadata.dart';
import 'package:borneo_kernel_abstractions/errors.dart';
import 'package:borneo_kernel_abstractions/models/discovered_device.dart';

import 'package:borneo_kernel_abstractions/models/supported_device_descriptor.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:borneo_kernel_abstractions/idriver.dart';

import '../borneo_device_api.dart';

class LyfiPaths {
  static final Uri info = Uri(path: '/borneo/lyfi/info');
  static final Uri status = Uri(path: '/borneo/lyfi/status');
  static final Uri mode = Uri(path: '/borneo/lyfi/mode');
  static final Uri color = Uri(path: '/borneo/lyfi/color');
  static final Uri schedule = Uri(path: '/borneo/lyfi/schedule');
  static final Uri schedulerEnabled =
      Uri(path: '/borneo/lyfi/scheduler-enabled');
}

class LyfiChannelInfo {
  final String name;
  final String color;
  final int powerRatio;

  const LyfiChannelInfo({
    required this.name,
    required this.color,
    required this.powerRatio,
  });

  factory LyfiChannelInfo.fromMap(dynamic map) {
    return LyfiChannelInfo(
      name: map['name'],
      color: map['color'],
      powerRatio: map['powerRatio'],
    );
  }
}

class LyfiDeviceInfo {
  final int channelCount;
  final List<LyfiChannelInfo> channels;

  const LyfiDeviceInfo(this.channelCount, this.channels);

  factory LyfiDeviceInfo.fromMap(CborMap cborMap) {
    final dynamic map = cborMap.toObject();
    return LyfiDeviceInfo(
        map['channelCount'],
        List<LyfiChannelInfo>.from(
          map['channels'].map((x) => LyfiChannelInfo.fromMap(x)),
        ));
  }
}

enum LedMode {
  normal,
  dimming,
  nightlight,
  preview;

  bool isLocked() {
    return this == normal || this == nightlight;
  }
}

class LyfiDeviceStatus {
  final LedMode currentMode;
  final bool schedulerEnabled;
  final bool unscheduled;
  final Duration nightlightRemaining;
  final int fanPower;
  final List<int> currentColor;
  final List<int> manualColor;

  double get brightness =>
      currentColor.fold(0, (p, v) => p + v).toDouble() *
      100.0 /
      (currentColor.length * 100.0);

  const LyfiDeviceStatus({
    required this.currentMode,
    required this.schedulerEnabled,
    required this.unscheduled,
    required this.nightlightRemaining,
    required this.fanPower,
    required this.currentColor,
    required this.manualColor,
  });

  factory LyfiDeviceStatus.fromMap(CborMap cborMap) {
    final dynamic map = cborMap.toObject();
    return LyfiDeviceStatus(
      currentMode: LedMode.values[map['currentMode']],
      schedulerEnabled: map['schedulerEnabled'],
      unscheduled: map['unscheduled'],
      nightlightRemaining: Duration(seconds: map['nlRemain']),
      fanPower: map['fanPower'],
      currentColor: List<int>.from(map['currentColor']),
      manualColor: List<int>.from(map['manualColor']),
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

abstract class ILyfiDeviceApi extends IBorneoDeviceApi {
  LyfiDeviceInfo getLyfiInfo(Device dev);
  Future<LyfiDeviceStatus> getLyfiStatus(Device dev);

  Future<LedMode> getMode(Device dev);
  Future<void> setMode(Device dev, LedMode mode);

  Future<bool> getSchedulerEnabled(Device dev);
  Future<void> setSchedulerEnabled(Device dev, bool isEnabled);

  Future<List<ScheduledInstant>> getSchedule(Device dev);
  Future<void> setSchedule(Device dev, Iterable<ScheduledInstant> schedule);

  Future<List<int>> getColor(Device dev);
  Future<void> setColor(Device dev, List<int> color);

  Future<int> getKeepTemp(Device dev);
}

class LyfiDriverData extends BorneoDriverData {
  int debugCounter = 0;
  final LyfiDeviceInfo _lyfiDeviceInfo;

  LyfiDriverData(super._coap, super._generalDeviceInfo, this._lyfiDeviceInfo);

  LyfiDeviceInfo get lyfiDeviceInfo {
    if (super.isDisposed) {
      ObjectDisposedException('The object has been disposed.');
    }
    return _lyfiDeviceInfo;
  }
}

class BorneoLyfiDriver
    with BorneoDeviceApiImpl
    implements IDriver, ILyfiDeviceApi {
  static const String lyfiCompatibleString = 'bst,borneo-lyfi';

  @override
  Future<bool> probe(Device dev) async {
    final probeCoapClient = CoapClient(dev.address);
    try {
      final generalDeviceInfo = await _getGeneralDeviceInfo(probeCoapClient);
      final lyfiInfo = await _getLyfiInfo(probeCoapClient);
      if (!kLyfiFWVersionConstraint.allows(generalDeviceInfo.fwVer)) {
        throw UnsupportedVersionError(
          'Unsupported firmware version',
          dev,
          currentVersion: generalDeviceInfo.fwVer,
          versionRange: kLyfiFWVersionConstraint,
        );
      }
      final coapClient = CoapClient(dev.address);
      dev.driverData = LyfiDriverData(coapClient, generalDeviceInfo, lyfiInfo);
      return true;
    } finally {
      probeCoapClient.close();
    }
  }

  @override
  Future<bool> remove(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    dd.dispose();
    return true;
  }

  @override
  Future<bool> heartbeat(Device dev) async {
    try {
      await getOnOff(dev);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {}

  Future<GeneralBorneoDeviceInfo> _getGeneralDeviceInfo(CoapClient coap) async {
    final response = await coap.get(
      Uri(path: '/borneo/info'),
      accept: CoapMediaType.applicationCbor,
    );
    return GeneralBorneoDeviceInfo.fromMap(
        cbor.decode(response.payload) as CborMap);
  }

  Future<LyfiDeviceInfo> _getLyfiInfo(CoapClient coap) async {
    final response = await coap.get(
      Uri(path: '/borneo/lyfi/info'),
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
  Future<LedMode> getMode(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    final value = await dd.coap.getCbor<int>(LyfiPaths.mode);
    return LedMode.values[value];
  }

  @override
  Future<void> setMode(Device dev, LedMode mode) async {
    final dd = dev.driverData as LyfiDriverData;
    await dd.coap.putCbor(LyfiPaths.mode, mode.index);
  }

  @override
  Future<bool> getSchedulerEnabled(Device dev) async {
    final dd = dev.driverData as LyfiDriverData;
    return await dd.coap.getCbor<bool>(LyfiPaths.schedulerEnabled);
  }

  @override
  Future<void> setSchedulerEnabled(Device dev, bool isEnabled) async {
    final dd = dev.driverData as LyfiDriverData;
    return await dd.coap.putCbor(LyfiPaths.schedulerEnabled, isEnabled);
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
}
