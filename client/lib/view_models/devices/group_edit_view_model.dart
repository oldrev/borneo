import 'package:borneo_app/models/devices/device_group_entity.dart';
import 'package:borneo_app/services/group_manager.dart';
import 'package:borneo_app/view_models/abstract_screen_view_model.dart';
import 'package:event_bus/event_bus.dart';
import 'package:logger/logger.dart';

import '../base_view_model.dart';

final class GroupEditArguments {
  final bool isCreation;
  final DeviceGroupEntity? model;

  const GroupEditArguments({required this.isCreation, this.model});
}

class GroupEditViewModel extends AbstractScreenViewModel
    with ViewModelEventBusMixin {
  final Logger? logger;
  final GroupManager _groupManager;
  final bool isCreation;
  late final String? id;
  late String name;
  late String notes;

  GroupEditViewModel(
    EventBus globalEventBus,
    this._groupManager, {
    required this.isCreation,
    DeviceGroupEntity? model,
    this.logger,
  }) {
    super.globalEventBus = globalEventBus;
    if (isCreation) {
      name = '';
      notes = '';
    } else {
      name = model!.name;
      notes = model.notes;
    }
    id = model?.id;
  }

  @override
  Future<void> onInitialize() async {
    // nothing to do
  }

  Future<void> submit() async {
    assert(!isBusy && isInitialized);

    setBusy(true);
    try {
      if (isCreation) {
        await _groupManager.create(name: name, notes: notes);
      } else {
        await _groupManager.update(id!, name: name, notes: notes);
      }
    } finally {
      setBusy(false);
    }
  }

  Future<void> delete() async {
    assert(!isCreation && !isBusy && isInitialized);
    setBusy(true, notify: false);
    try {
      await _groupManager.delete(id!);
    } catch (e, stackTrace) {
      notifyAppError('Failed to delete group `$name`',
          error: e, stackTrace: stackTrace);
    } finally {
      setBusy(false, notify: false);
    }
  }
}