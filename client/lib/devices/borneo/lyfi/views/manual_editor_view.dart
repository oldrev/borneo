import 'package:borneo_app/devices/borneo/lyfi/views/brightness_slider_list.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/color_chart.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/lyfi_driver.dart';
import 'package:flutter/material.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/devices/borneo/lyfi/view_models/lyfi_view_model.dart';
import 'package:borneo_app/views/common/hex_color.dart';
import 'package:borneo_app/widgets/value_listenable_builders.dart';
import '../view_models/manual_editor_view_model.dart';

class ManualEditorView extends StatelessWidget {
  const ManualEditorView({super.key});

  Widget buildSliders(BuildContext context) {
    return Consumer<ManualEditorViewModel>(
      builder: (context, vm, _) {
        if (vm.isInitialized) {
          return Selector<ManualEditorViewModel, bool>(
            selector: (_, editor) => editor.canChangeColor,
            builder:
                (_, canChangeColor, __) =>
                    BrightnessSliderList(context.read<ManualEditorViewModel>(), disabled: !canChangeColor),
          );
        } else {
          return Container();
        }
      },
    );
  }

  List<BarChartGroupData> buildGroupDataItems(BuildContext context, ManualEditorViewModel vm) {
    int index = 0;
    if (vm.isInitialized) {
      return vm.deviceInfo.channels.map((ch) {
        final channel = vm.channels[index];
        final g = makeGroupData(context, ch, index, channel.value.toDouble());
        index++;
        return g;
      }).toList();
    } else {
      return [];
    }
  }

  BarChartGroupData makeGroupData(BuildContext context, LyfiChannelInfo ch, int x, double y) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          borderRadius: BorderRadius.circular(4),
          toY: y,
          color: HexColor.fromHex(ch.color),
          width: 16,
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            fromY: 0,
            toY: ch.powerRatio.toDouble(),
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
      ],
    );
  }

  Widget buildTitles(BuildContext context, ManualEditorViewModel vm, double value) {
    if (vm.isInitialized) {
      final index = value.toInt();
      final ch = vm.deviceInfo.channels[index];
      return Text(ch.name, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor));
    } else {
      return Text("N/A");
    }
  }

  Widget buildGraph(BuildContext context) {
    return Consumer<ManualEditorViewModel>(
      builder: (context, vm, _) {
        return MultiValueListenableBuilder<int>(
          valueNotifiers: vm.channels,
          builder:
              (context, values, _) => LyfiColorChart(
                BarChartData(
                  barGroups: buildGroupDataItems(context, vm),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      axisNameSize: 24,
                      sideTitles: SideTitles(
                        reservedSize: 24,
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
              ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: context.read<LyfiViewModel>().currentEditor! as ManualEditorViewModel,
      builder:
          (context, child) => Column(
            spacing: 16,
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainer,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: AspectRatio(aspectRatio: 2.75, child: buildGraph(context)),
              ),
              Expanded(child: buildSliders(context)),
            ],
          ),
    );
  }
}
