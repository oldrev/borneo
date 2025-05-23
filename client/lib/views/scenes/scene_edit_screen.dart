import 'package:borneo_app/services/scene_manager.dart';
import 'package:borneo_app/view_models/scenes/scene_edit_view_model.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import '../../widgets/confirmation_sheet.dart';

class SceneEditScreen extends StatelessWidget {
  final SceneEditArguments args;
  final _formKey = GlobalKey<FormState>();

  SceneEditScreen({required this.args, super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<SceneEditViewModel>(
    create: createViewModel,
    builder:
        (context, child) => FutureBuilder(
          future:
              context.read<SceneEditViewModel>().isInitialized ? null : context.read<SceneEditViewModel>().initialize(),
          builder: (context, snapshot) {
            final vm = context.read<SceneEditViewModel>();
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(
                child: Text(context.translate('Error: {errMsg}', nArgs: {'errMsg': snapshot.error.toString()})),
              );
            } else {
              return Scaffold(
                appBar: AppBar(
                  title: Text(vm.isCreation ? context.translate('New Scene') : context.translate('Edit Scene')),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  actions: buildActions(context, args),
                ),
                body: buildBody(context),
              );
            }
          },
        ),
  );

  SceneEditViewModel createViewModel(BuildContext context) {
    return SceneEditViewModel(
      context.read<EventBus>(),
      context.read<SceneManager>(),
      isCreation: args.isCreation,
      model: args.model,
      logger: context.read<Logger>(),
    );
  }

  List<Widget> makePropertyTiles(BuildContext context) {
    final vm = context.read<SceneEditViewModel>();
    return [
      TextFormField(
        initialValue: vm.name,
        decoration: InputDecoration(
          labelText: context.translate('Name'),
          hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
          hintText: context.translate('Enter the required scene name'),
        ),
        validator: (value) {
          if (value?.isEmpty ?? false) {
            return context.translate('Please enter the scene name');
          }
          return null;
        },
        onSaved: (value) {
          vm.name = value ?? '';
        },
      ),
      SizedBox(height: 16),
      TextFormField(
        initialValue: vm.notes,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(
          hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
          hintText: context.translate('Enter the optional notes for this scene'),
          labelText: context.translate('Notes'),
        ),
        onSaved: (value) {
          vm.notes = value ?? '';
        },
      ),
      SizedBox(height: 24),
      ElevatedButton(
        onPressed:
            vm.isBusy
                ? null
                : () async {
                  if (_formKey.currentState?.validate() ?? false) {
                    _formKey.currentState!.save();
                    await vm.submit();
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  }
                },
        child: Text(context.translate('Submit')),
      ),
    ];
  }

  ListView buildList(BuildContext context) {
    final items = makePropertyTiles(context);
    return ListView.builder(
      shrinkWrap: true,
      itemBuilder: (BuildContext context, int index) => items[index],
      itemCount: items.length,
    );
  }

  Widget buildBody(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Form(key: _formKey, child: buildList(context)),
    );
  }

  List<Widget> buildActions(BuildContext context, SceneEditArguments args) {
    final vm = context.read<SceneEditViewModel>();
    return [
      if (vm.deletionAvailable)
        IconButton(
          onPressed:
              vm.isBusy
                  ? null
                  : () {
                    showModalBottomSheet(
                      context: context,
                      builder: (BuildContext context) {
                        return ConfirmationSheet(
                          message: context.translate(
                            'Are you sure you want to delete this device group? The devices within this group will not be deleted but will be moved to the "Ungrouped" group.',
                          ),
                          okPressed: () async {
                            await vm.delete();
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          },
                        );
                      },
                    );
                  },
          icon: Icon(Icons.delete_outline),
        ),
    ];
  }
}
