import 'dart:ui' show PointerDeviceKind;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'app_keys.dart';
import 'theme.dart';

import 'screens/splash_screen.dart';
import 'screens/role_select_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/coach_login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/recipes_screen.dart';
import 'screens/scaling_screen.dart';
import 'screens/grocery_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/coach_dashboard_screen.dart';
import 'screens/client_list_screen.dart';
import 'screens/set_targets_screen.dart';
import 'screens/client_progress_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/mission_screen.dart';
import 'screens/food_search_screen.dart';
import 'screens/nutrition_screen.dart';
import 'services/alarm_service.dart';
import 'screens/planned_meal_screen.dart';
import 'screens/account_settings_screen.dart';
import 'screens/coach_info_screen.dart';
import 'screens/notification_prefs_screen.dart';
import 'screens/privacy_security_screen.dart';
import 'screens/help_support_screen.dart';
import 'screens/coach_inbox_screen.dart';
import 'screens/notifications_screen.dart';
import 'services/in_app_notifier.dart';
import 'screens/coach_profile_screen.dart';
import 'widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const NutriFitApp());
}

class NutriFitApp extends StatelessWidget {
  const NutriFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        Provider<AlarmService>(create: (context) => AlarmService(context.read<ApiService>())),
        ChangeNotifierProvider<InAppNotifier>(create: (context) => InAppNotifier(context.read<ApiService>())),
        Provider<NotificationService>(create: (context) => NotificationService(context.read<ApiService>())),
        ChangeNotifierProxyProvider<ApiService, AuthService>(
          create: (context) => AuthService(context.read<ApiService>()),
          update: (context, api, previous) => previous ?? AuthService(api),
        ),
      ],
      child: _NotifierHost(child: MaterialApp(
        title: 'NutriFit',
        scaffoldMessengerKey: messengerKey,
        navigatorKey: navigatorKey,
        scrollBehavior: const _DragScrollBehavior(),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.userTheme,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          final name = settings.name ?? '/';

          // Dynamic route: /scale or /scale/<recipeId>
          if (name == '/scale' || name.startsWith('/scale/')) {
            final parts = name.split('/');
            final recipeId = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
            final args = settings.arguments is Map ? settings.arguments as Map : const {};
            return MaterialPageRoute(
              builder: (_) => AuthGate(
                requiredRole: 'user',
                child: ScalingScreen(
                  recipeId: recipeId,
                  mealType: (args['mealType'] as String?) ?? 'Lunch',
                  futureMeal: (args['futureMeal'] as String?) ?? 'not_sure',
                ),
              ),
            );
          }

          // Planned meal: /planned/<id>
          if (name.startsWith('/planned/')) {
            final id = name.substring('/planned/'.length);
            return MaterialPageRoute(builder: (_) => AuthGate(requiredRole: 'user', child: PlannedMealScreen(plannedId: id)));
          }

          // Chat: /chat (client's own thread) or /chat/<clientId> (coach opening a client's thread)
          if (name == '/chat' || name.startsWith('/chat/')) {
            final parts = name.split('/');
            final clientId = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
            return MaterialPageRoute(builder: (_) => AuthGate(requiredRole: clientId == null ? 'user' : 'coach', child: ChatScreen(clientId: clientId)));
          }
          if (name == '/notifications') {
            return MaterialPageRoute(builder: (_) => const AuthGate(child: NotificationsScreen()), settings: settings);
          }
          if (name == '/coach/profile') {
            return MaterialPageRoute(builder: (_) => const AuthGate(requiredRole: 'coach', child: CoachProfileScreen()));
          }
          if (name == '/settings/account' || name == '/settings/notifications' || name == '/settings/privacy') {
            // Shared settings pages: open to both clients and coaches.
            final shared = <String, Widget>{
              '/settings/account': const AccountSettingsScreen(),
              '/settings/notifications': const NotificationPrefsScreen(),
              '/settings/privacy': const PrivacySecurityScreen(),
            };
            return MaterialPageRoute(builder: (_) => AuthGate(child: shared[name]!), settings: settings);
          }
          if (name == '/coach/messages') {
            return MaterialPageRoute(builder: (_) => const AuthGate(requiredRole: 'coach', child: CoachInboxScreen()));
          }

          // Coach client routes: /coach/clients, /coach/clients/<id>, /coach/clients/<id>/targets
          if (name.startsWith('/coach/clients')) {
            final parts = name.split('/').where((p) => p.isNotEmpty).toList(); // [coach, clients, id?, targets?]
            if (parts.length == 2) {
              return MaterialPageRoute(builder: (_) => const AuthGate(requiredRole: 'coach', child: ClientListScreen()));
            }
            final clientId = parts[2];
            if (parts.length == 4 && parts[3] == 'targets') {
              return MaterialPageRoute(builder: (_) => AuthGate(requiredRole: 'coach', child: SetTargetsScreen(clientId: clientId)));
            }
            return MaterialPageRoute(builder: (_) => AuthGate(requiredRole: 'coach', child: ClientProgressScreen(clientId: clientId)));
          }

          final publicBuilders = <String, WidgetBuilder>{
            '/': (_) => const SplashScreen(),
            '/role': (_) => const RoleSelectScreen(),
            '/login': (_) => const LoginScreen(),
            '/register': (_) => const RegisterScreen(),
            '/coach-login': (_) => const CoachLoginScreen(),
          };
          if (publicBuilders.containsKey(name)) {
            return MaterialPageRoute(builder: publicBuilders[name]!, settings: settings);
          }

          final userBuilders = <String, WidgetBuilder>{
            '/home': (_) => const HomeScreen(),
            '/recipes': (_) => const RecipesScreen(),
            '/grocery': (_) => const GroceryScreen(),
            '/reminders': (_) => const RemindersScreen(),
            '/profile': (_) => const ProfileScreen(),
            '/mission': (_) => const MissionScreen(),
            '/foods': (_) => const FoodSearchScreen(),
            '/nutrition': (_) => const NutritionScreen(),
            '/settings/account': (_) => const AccountSettingsScreen(),
            '/settings/coach': (_) => const CoachInfoScreen(),
            '/settings/notifications': (_) => const NotificationPrefsScreen(),
            '/settings/privacy': (_) => const PrivacySecurityScreen(),
            '/settings/help': (_) => const HelpSupportScreen(),
          };
          if (userBuilders.containsKey(name)) {
            return MaterialPageRoute(builder: (context) => AuthGate(requiredRole: 'user', child: userBuilders[name]!(context)), settings: settings);
          }

          if (name == '/coach') {
            return MaterialPageRoute(builder: (_) => const AuthGate(requiredRole: 'coach', child: CoachDashboardScreen()), settings: settings);
          }

          return MaterialPageRoute(builder: (_) => const SplashScreen());
        },
      )),
    );
  }
}

/// Starts and stops the in-app notification polling when the user signs in or out.
class _NotifierHost extends StatefulWidget {
  final Widget child;
  const _NotifierHost({required this.child});
  @override
  State<_NotifierHost> createState() => _NotifierHostState();
}

class _NotifierHostState extends State<_NotifierHost> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final notifier = context.read<InAppNotifier>();
    final token = auth.token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (token != null && auth.role != null) {
        notifier.start(token, auth.role!);
      } else {
        notifier.stop();
      }
    });
    return widget.child;
  }
}

/// Lets lists be dragged with a mouse or trackpad too (on the web only touch can drag by default).
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
