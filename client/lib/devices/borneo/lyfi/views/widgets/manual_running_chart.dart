import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/color_chart.dart';
import 'package:borneo_app/views/common/hex_color.dart';
import 'package:borneo_app/widgets/value_listenable_builders.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/lyfi_driver.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ManualRunningChart extends StatelessWidget {
  const ManualRunningChart({super.key});

  List<BarChartGroupData> buildGroupDataItems(BuildContext context, LyfiViewModel vm) {
    int index = 0;
    return vm.lyfiDeviceInfo.channels.map((ch) {
      final channel = vm.channels[index];
      final g = makeGroupData(context, ch, index, channel.value.toDouble());
      index++;
      return g;
    }).toList();
  }

  BarChartGroupData makeGroupData(BuildContext context, LyfiChannelInfo ch, int x, double y) {
    final primaryColor = HexColor.fromHex(ch.color);
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          borderRadius: BorderRadius.circular(5),
          toY: y,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryColor, Color.lerp(primaryColor, Colors.white, 0.7)!],
          ),
          width: 16,
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            fromY: 0,
            toY: lyfiBrightnessMax.toDouble(),
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),
      ],
    );
  }

  Widget buildTitles(BuildContext context, LyfiViewModel vm, double value) {
    final index = value.toInt();
    final ch = vm.lyfiDeviceInfo.channels[index];
    return Text(
      ch.name,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<LyfiViewModel>(
      builder:
          (context, vm, _) => MultiValueListenableBuilder<int>(
            valueNotifiers: vm.channels,
            builder:
                (context, values, _) => Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child:
                      vm.isOnline
                          ? LyfiColorChart(
                            BarChartData(
                              barGroups: buildGroupDataItems(context, vm),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, _) => buildTitles(context, vm, value),
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              barTouchData: BarTouchData(enabled: true),
                              gridData: FlGridData(show: false),
                            ),
                          )
                          : Center(
                            child: Text(
                              "Device Offline.",
                              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error),
                            ),
                          ),
                ),
          ),
    );
  }
}
