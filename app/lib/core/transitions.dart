// Owned by AppWand. How pages come on screen: the app's transition is picked
// in AppWand ("App theme", Motion) and router.g.dart can give a page its own.
// Pages move inside AppShell (widgets.dart), so the navigation stays put.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart' show AppTransition, appTransition;

export 'theme.dart' show AppTransition;

/// The page go_router shows for [child], coming on screen with [transition]
/// (the app's own when null).
Page<void> appPage(GoRouterState state, Widget child, {AppTransition? transition}) {
  final kind = transition ?? appTransition;
  final name = state.name ?? state.path;
  final arguments = {...state.pathParameters, ...state.uri.queryParameters};
  switch (kind) {
    case AppTransition.platform:
      return MaterialPage<void>(
        key: state.pageKey,
        name: name,
        arguments: arguments,
        restorationId: state.pageKey.value,
        child: child,
      );
    case AppTransition.none:
      return NoTransitionPage<void>(
        key: state.pageKey,
        name: name,
        arguments: arguments,
        restorationId: state.pageKey.value,
        child: child,
      );
    default:
      final duration = kind == AppTransition.slide || kind == AppTransition.slideUp
          ? const Duration(milliseconds: 350)
          : const Duration(milliseconds: 300);
      return CustomTransitionPage<void>(
        key: state.pageKey,
        name: name,
        arguments: arguments,
        restorationId: state.pageKey.value,
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            _transition(kind, context, animation, secondaryAnimation, child),
        child: child,
      );
  }
}

/// [route] with its builder shown through [appPage], so screens written with
/// `builder:` (the sign-in screens' authRoutes) come on screen like the rest.
RouteBase withAppTransition(RouteBase route) {
  if (route is! GoRoute) return route;
  final builder = route.builder;
  return GoRoute(
    path: route.path,
    name: route.name,
    parentNavigatorKey: route.parentNavigatorKey,
    redirect: route.redirect,
    onExit: route.onExit,
    builder: builder,
    pageBuilder: route.pageBuilder ??
        (builder == null ? null : (context, state) => appPage(state, builder(context, state))),
    routes: [for (final child in route.routes) withAppTransition(child)],
  );
}

/// [animation] brings this page in; [secondary] moves it aside while the
/// next page comes in over it.
Widget _transition(
  AppTransition kind,
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondary,
  Widget child,
) {
  // The device's "reduce motion" setting turns every transition off.
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;

  Animation<T> drive<T>(Animation<double> parent, Tween<T> tween, Curve curve) =>
      parent.drive(tween.chain(CurveTween(curve: curve)));

  switch (kind) {
    case AppTransition.fade:
      return FadeTransition(opacity: drive(animation, Tween(begin: 0.0, end: 1.0), Curves.easeOut), child: child);
    case AppTransition.fadeThrough:
      const enter = Interval(0.35, 1, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: drive(secondary, Tween(begin: 1.0, end: 0.0), const Interval(0, 0.35, curve: Curves.easeIn)),
        child: FadeTransition(
          opacity: drive(animation, Tween(begin: 0.0, end: 1.0), enter),
          child: ScaleTransition(scale: drive(animation, Tween(begin: 0.92, end: 1.0), enter), child: child),
        ),
      );
    case AppTransition.slide:
      return SlideTransition(
        position: drive(secondary, Tween(begin: Offset.zero, end: const Offset(-0.3, 0)), Curves.easeOutCubic),
        child: SlideTransition(
          position: drive(animation, Tween(begin: const Offset(1, 0), end: Offset.zero), Curves.easeOutCubic),
          child: child,
        ),
      );
    case AppTransition.slideUp:
      return SlideTransition(
        position: drive(animation, Tween(begin: const Offset(0, 1), end: Offset.zero), Curves.easeOutCubic),
        child: child,
      );
    case AppTransition.zoom:
      return ScaleTransition(
        scale: drive(secondary, Tween(begin: 1.0, end: 1.05), Curves.easeOutCubic),
        child: FadeTransition(
          opacity: drive(animation, Tween(begin: 0.0, end: 1.0), const Interval(0, 0.6, curve: Curves.easeOut)),
          child: ScaleTransition(scale: drive(animation, Tween(begin: 0.85, end: 1.0), Curves.easeOutCubic), child: child),
        ),
      );
    default:
      return child;
  }
}
