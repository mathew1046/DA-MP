import 'package:flutter/material.dart';

import 'data/store.dart';
import 'ml/models.dart';
import 'ui/insights_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';
import 'ui/today_screen.dart';

/// Shared services for the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.store, required this.detector, required this.profileModel, required super.child});

  final AppStore store;
  final FogDetector detector;
  final GaitProfileModel profileModel;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

class StepCueApp extends StatelessWidget {
  const StepCueApp({super.key, required this.store, required this.detector, required this.profileModel});

  final AppStore store;
  final FogDetector detector;
  final GaitProfileModel profileModel;

  @override
  Widget build(BuildContext context) => AppScope(
        store: store,
        detector: detector,
        profileModel: profileModel,
        child: MaterialApp(
          title: 'StepCue',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final scale = media.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.6);
            return MediaQuery(data: media.copyWith(textScaler: scale), child: child!);
          },
          home: const HomeShell(),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: [
              // Not const: these read the store and must rebuild when it changes.
              TodayScreen(onOpenInsights: () => setState(() => _tab = 1)),
              InsightsScreen(key: const ValueKey('insights')),
              SettingsScreen(key: const ValueKey('settings')),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Insights'),
            NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
