import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/baby/baby_overview_screen.dart';
import '../../features/baby/baby_setup_screen.dart';
import '../../features/baby/baby_entry_screen.dart';
import '../../features/baby/baby_import_screen.dart';
import '../../features/baby/baby_scan_screen.dart';
import '../../features/baby/baby_inbox_screen.dart';
import '../utils/baby_timeline_utils.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/baby',
  routes: [
    GoRoute(
      path: '/baby',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: BabyOverviewScreen(),
      ),
    ),
    GoRoute(
      path: '/baby/setup',
      pageBuilder: (context, state) => CustomTransitionPage(
        child: const BabySetupScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/baby/slot/:slotKey',
      pageBuilder: (context, state) {
        final slotKey = state.pathParameters['slotKey']!;
        final slot = BabyTimelineUtils.slotForKey(slotKey);
        return CustomTransitionPage(
          child: BabyEntryScreen(slot: slot),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut)),
              child: child,
            );
          },
        );
      },
    ),
    GoRoute(
      path: '/baby/scan',
      pageBuilder: (context, state) => CustomTransitionPage(
        child: const BabyScanEntryPoint(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/baby/import',
      pageBuilder: (context, state) => CustomTransitionPage(
        child: const BabyImportEntryPoint(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/baby/inbox',
      pageBuilder: (context, state) => CustomTransitionPage(
        child: const BabyInboxScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
      ),
    ),
    GoRoute(
      path: '/',
      redirect: (context, state) => '/baby',
    ),
  ],
);
