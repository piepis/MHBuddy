import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'app_model.dart';
import 'l10n.dart';
import 'pages.dart';
import 'shell.dart';

void main() {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  L10n.check();
  final model = AppModel();
  final router = GoRouter(
    refreshListenable: model,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(path: '/me', builder: (_, _) => const AccountPage()),
      GoRoute(path: '/offline', builder: (_, _) => const OfflinePage()),
      GoRoute(path: '/builds/:publicId', builder: (_, state) => PublicBuildPage(id: state.pathParameters['publicId']!)),
      GoRoute(path: '/g/:gameId', builder: (_, state) => HomePage(routeGameId: state.pathParameters['gameId'])),
      GoRoute(
        path: '/g/:gameId/entries',
        builder: (_, state) => CatalogPage(gameId: state.pathParameters['gameId']!, initialQuery: state.uri.queryParameters['q'] ?? ''),
      ),
      GoRoute(
        path: '/g/:gameId/entries/:kind/:entryId',
        builder: (_, state) => EntryPage(
          gameId: state.pathParameters['gameId']!,
          kind: state.pathParameters['kind']!,
          entryId: state.pathParameters['entryId']!,
        ),
      ),
      GoRoute(
        path: '/g/:gameId/maps',
        builder: (_, state) => MapPage(gameId: state.pathParameters['gameId']!, mapId: 'fixture-ancient-forest', resourceId: state.uri.queryParameters['resource']),
      ),
      GoRoute(
        path: '/g/:gameId/maps/:mapId',
        builder: (_, state) => MapPage(gameId: state.pathParameters['gameId']!, mapId: state.pathParameters['mapId']!, resourceId: state.uri.queryParameters['resource']),
      ),
      GoRoute(path: '/g/:gameId/builds', builder: (_, state) => BuildsPage(gameId: state.pathParameters['gameId']!)),
      GoRoute(path: '/g/:gameId/events', builder: (_, state) => EventsPage(gameId: state.pathParameters['gameId']!)),
      GoRoute(
        path: '/g/:gameId/events/:id',
        builder: (_, state) => EventDetailPage(gameId: state.pathParameters['gameId']!, id: state.pathParameters['id']!),
      ),
    ],
  );
  runApp(MhApp(model: model, router: router));
  SemanticsBinding.instance.ensureSemantics();
  model.boot();
}

class MhApp extends StatelessWidget {
  const MhApp({required this.model, required this.router, super.key});
  final AppModel model;
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MhScope(
      model: model,
      child: MaterialApp.router(routerConfig: router, debugShowCheckedModeBanner: false, title: 'MH伙伴助手'),
    );
  }
}
