import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/routes/app_router.dart';
import 'config/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/calendar/presentation/providers/calendar_provider.dart';
import 'features/manual_input/presentation/providers/manual_input_provider.dart';
import 'features/onboarding/presentation/providers/onboarding_provider.dart';
import 'features/plant_database/presentation/providers/plant_provider.dart';
import 'shared/providers/firebase_providers.dart';
import 'shared/services/session_service.dart';

/// Root widget for the GardNx application.
class GardNxApp extends ConsumerStatefulWidget {
  const GardNxApp({super.key});

  @override
  ConsumerState<GardNxApp> createState() => _GardNxAppState();
}

class _GardNxAppState extends ConsumerState<GardNxApp>
    with WidgetsBindingObserver {
  final SessionService _sessionService = SessionService();
  Timer? _inactivityTimer;

  static const _inactivityTimeout = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_sessionService.enforceSession);
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.microtask(_sessionService.enforceSession);
      _resetInactivityTimer();
    } else if (state == AppLifecycleState.paused) {
      _inactivityTimer?.cancel();
    }
  }

  void _resetInactivityTimer() {
    // Only run the inactivity timer when a user is actually signed in.
    final user = ref.read(currentUserProvider);
    if (user == null) {
      _inactivityTimer?.cancel();
      return;
    }
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, _signOutDueToInactivity);
  }

  Future<void> _signOutDueToInactivity() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return; // already signed out
    try {
      await ref.read(signOutProvider)();
    } catch (_) {
      // Ignore — GoRouter will redirect to login on auth state change anyway.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Load onboarding flag early so the router redirect can check it.
    ref.watch(loadOnboardingProvider);

    // Invalidate user-scoped providers whenever the signed-in uid changes,
    // so a returning user never inherits the previous user's in-memory state
    // (active garden, drawn beds, selected day, cached plant list).
    ref.listen(firebaseAuthStateProvider, (prev, next) {
      final prevUid = prev?.valueOrNull?.uid;
      final nextUid = next.valueOrNull?.uid;
      if (prevUid == nextUid) return;
      ref.invalidate(activeGardenIdProvider);
      ref.invalidate(selectedCalendarDayProvider);
      ref.invalidate(manualInputProvider);
      ref.invalidate(selectedBedIdProvider);
      ref.invalidate(allPlantsProvider);
    });

    final router = ref.watch(appRouterProvider);

    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: MaterialApp.router(
        title: 'MYGarden Planner',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
  }
}
