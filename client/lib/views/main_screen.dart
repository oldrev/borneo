import 'package:borneo_app/routes/app_routes.dart';
import 'package:borneo_app/services/blob_manager.dart';
import 'package:borneo_app/services/group_manager.dart';
import 'package:borneo_app/services/routine_manager.dart';
import 'package:borneo_app/view_models/devices/group_edit_view_model.dart';
import 'package:borneo_app/view_models/scenes/scene_edit_view_model.dart';
import 'package:borneo_app/views/devices/group_edit_screen.dart';
import 'package:borneo_app/views/scenes/scene_edit_screen.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '../services/device_manager.dart';
import '../services/scene_manager.dart';
import '../view_models/devices/grouped_devices_view_model.dart';
import '../view_models/scenes/scenes_view_model.dart';
import '../view_models/my_view_model.dart';
import 'scenes/scenes_screen.dart';
import 'devices/devices_screen.dart';
import 'my_screen.dart';

import '../view_models/main_view_model.dart';

enum PlusMenuIndexes {
  addScene,
  addGroup,
  addDevice,
}

class ErrorSnackBarListener extends StatelessWidget {
  final Widget child;
  const ErrorSnackBarListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<MainViewModel>(
      builder: (context, vm, child) {
        if (vm.hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(vm.errorMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer)),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                action: SnackBarAction(
                  label: 'Dismiss',
                  onPressed: () {
                    if (!vm.isDisposed) {
                      vm.clearError();
                    }
                  },
                ),
              ),
            );
          });
        }
        return child!;
      },
      child: child,
    );
  }
}

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MyAppBar({super.key});
  String _getTitle(BuildContext context, MainViewModel vm) {
    switch (vm.currentTabIndex) {
      case TabIndices.devices:
        return vm.currentSceneName;
      case TabIndices.scenes:
        return context.translate("Scenes");
      case TabIndices.my:
        return context.translate("My");
    }
  }

  Future<void> showDiscoveryScreen(BuildContext context) async {
    await Navigator.of(context).pushNamed(AppRoutes.kDeviceDiscovery);
  }

  Future<void> showNewGroupScreen(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupEditScreen(),
        settings:
            RouteSettings(arguments: GroupEditArguments(isCreation: true)),
      ),
    );
  }

  Future<void> showNewSceneScreen(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => SceneEditScreen(
                args: SceneEditArguments(isCreation: true),
              )),
    );
  }

  PopupMenuButton buildAddButtons(BuildContext context) {
    return PopupMenuButton<PlusMenuIndexes>(
      icon: Icon(Icons.add_outlined),
      onSelected: (value) {
        switch (value) {
          case PlusMenuIndexes.addGroup:
            {
              showNewGroupScreen(context);
              break;
            }
          case PlusMenuIndexes.addScene:
            {
              showNewSceneScreen(context);
              break;
            }
          case PlusMenuIndexes.addDevice:
            {
              showDiscoveryScreen(context);
              break;
            }
        }
        // Handle menu item selection
      },
      itemBuilder: (BuildContext context) {
        return <PopupMenuEntry<PlusMenuIndexes>>[
          PopupMenuItem<PlusMenuIndexes>(
            value: PlusMenuIndexes.addDevice,
            child: Text(context.translate('Add New Devices')),
          ),
          PopupMenuDivider(),
          PopupMenuItem<PlusMenuIndexes>(
            value: PlusMenuIndexes.addScene,
            child: Text(context.translate('Add Scene')),
          ),
          PopupMenuItem<PlusMenuIndexes>(
            value: PlusMenuIndexes.addGroup,
            child: Text(context.translate('Add Devices Group')),
          ),
        ];
      },
    );
  }

  @override
  Widget build(Object context) {
    final bc = context as BuildContext;
    final vm = bc.read<MainViewModel>();
    return AppBar(
      /*
        flexibleSpace: FlexibleSpaceBar(
          background: Image.asset(
            'assets/images/scene-bg-default.jpg',
            fit: BoxFit.cover,
          ),
        ),
        */
      title: Column(children: [
        Text(_getTitle(context, vm)),
      ]),
      actions: [
        Selector<MainViewModel,
            ({bool isInit, bool isScanningDevices, TabIndices index})>(
          selector: (_, vm) => (
            isInit: vm.isInitialized,
            isScanningDevices: vm.isScanningDevices,
            index: vm.currentTabIndex
          ),
          builder: (_, vm, __) => !vm.isInit || vm.isScanningDevices
              ? SizedBox(
                  height: 24, width: 24, child: CircularProgressIndicator())
              : buildAddButtons(context),
        ),
      ],
    );
  }

  @override
  // TODO: implement preferredSize
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  Widget buildScaffold(BuildContext context) {
    return Selector<MainViewModel, TabIndices>(
      selector: (context, vm) => vm.currentTabIndex,
      builder: (context, tabIndex, child) => Scaffold(
        appBar: null,

        // page body
        body: ErrorSnackBarListener(
          child: Selector<MainViewModel, TabIndices>(
            selector: (context, vm) => vm.currentTabIndex,
            builder: (context, index, child) {
              switch (index) {
                case TabIndices.devices:
                  return const DevicesScreen();
                case TabIndices.scenes:
                  return const ScenesScreen();
                case TabIndices.my:
                  return const MyScreen();
                default:
                  return const DevicesScreen();
              }
            },
          ),
        ),

        // bottom
        bottomNavigationBar: Consumer<MainViewModel>(
          builder: (context, viewModel, child) {
            return BottomNavigationBar(
              currentIndex: viewModel.currentTabIndex.index,
              onTap: (index) {
                if (index != viewModel.currentTabIndex.index) {
                  viewModel.setIndex(TabIndices.values[index]);
                }
              },
              items: [
                BottomNavigationBarItem(
                  icon: Icon(Icons.house_outlined),
                  label: context.translate('Scenes'),
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.device_hub),
                  label: context.translate('Devices'),
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: context.translate('My'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void showRescanDevicesDialog(BuildContext context) {
    Navigator.of(context).pop();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Loading...'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(context);
                },
                child: Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final bus = context.read<EventBus>();
        final bm = context.read<IBlobManager>();
        final sm = context.read<SceneManager>();
        final gm = context.read<GroupManager>();
        final dm = context.read<DeviceManager>();
        final vm =
            MainViewModel(bus, bm, sm, gm, dm, logger: context.read<Logger>());
        return vm;
      },
      lazy: false,
      child: Selector<MainViewModel, bool>(
        selector: (context, vm) => vm.isInitialized,
        builder: (context, viewModel, child) {
          return FutureBuilder(
            future: context.read<MainViewModel>().isInitialized
                ? null
                : context.read<MainViewModel>().initialize(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              } else if (snapshot.hasError) {
                return Scaffold(
                    body: Center(child: Text('Error: ${snapshot.error}')));
              } else {
                return MultiProvider(providers: [
                  ChangeNotifierProvider<ScenesViewModel>(
                      create: (context) => ScenesViewModel(
                            context.read<EventBus>(),
                            context.read<SceneManager>(),
                            context.read<DeviceManager>(),
                            context.read<RoutineManager>(),
                          ),
                      lazy: true),

                  ChangeNotifierProvider(
                      create: (_) => MyViewModel(), lazy: true),

                  // Device-related pages
                  ChangeNotifierProvider(
                      create: (context) {
                        final logger = context.read<Logger>();
                        final globalEventBus = context.read<EventBus>();
                        final sm = context.read<SceneManager>();
                        final gm = context.read<GroupManager>();
                        final dm = context.read<DeviceManager>();
                        return GroupedDevicesViewModel(
                            globalEventBus, sm, gm, dm,
                            logger: logger);
                      },
                      lazy: true),
                ], child: buildScaffold(context));
              }
            },
          );
        },
      ),
    );
  }
}