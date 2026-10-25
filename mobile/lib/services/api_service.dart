import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

/// Thin wrapper around the FastAPI backend. Pass the current auth token (either a
/// real Firebase ID token, or the dev-mode "fakeuid:..." token) with every call.
class ApiService {
  /// Point this at your deployed FastAPI backend, or http://10.0.2.2:8000 for the
  /// Android emulator talking to a backend running on your own machine
  /// (10.0.2.2 is the emulator's alias for the host machine's localhost).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  Future<dynamic> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PUT':
        response = await http.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PATCH':
        response = await http.patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        throw ApiException('Unsupported method $method');
    }

    Map<String, dynamic>? data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        data = null;
      }
    }

    if (response.statusCode >= 400) {
      final message = data?['detail']?.toString() ?? 'Request failed (${response.statusCode})';
      throw ApiException(message, response.statusCode);
    }
    return data;
  }

  // --- Auth ---
  // register() is real production code: the backend creates both the Firebase
  // Auth account (via admin privileges) and the Firestore profile in one call.
  Future<Map<String, dynamic>> register(Map<String, dynamic> payload) async =>
      await _request('POST', '/auth/register', body: payload) as Map<String, dynamic>;

  // devLogin exists only for testing the backend directly (e.g. via curl) before
  // a real Firebase project is wired up. The Flutter app never calls this —
  // it signs in through FirebaseAuth directly, see AuthService.login().
  Future<Map<String, dynamic>> devLogin(String email, String password, String role) async =>
      await _request('POST', '/auth/login', body: {'email': email, 'password': password, 'role': role}) as Map<String, dynamic>;

  Future<Map<String, dynamic>> me(String token) async =>
      await _request('GET', '/auth/me', token: token) as Map<String, dynamic>;
  Future<void> registerFcmToken(String token, String deviceToken) async =>
      await _request('PATCH', '/auth/fcm-token', token: token, body: {'token': deviceToken});

  // --- Recipes ---
  Future<Map<String, dynamic>> recipes(String token, {String? tag, String? search}) async {
    final query = <String, String>{};
    if (tag != null && tag != 'All') query['tag'] = tag;
    if (search != null && search.isNotEmpty) query['search'] = search;
    return await _request('GET', '/recipes', token: token, query: query) as Map<String, dynamic>;
  }

  /// Preview only: asks the server to optimise the recipe's ingredients for this meal. Nothing is saved.
  Future<Map<String, dynamic>> optimizeRecipe(String token, String recipeId, String mealType, String futureMeal) async =>
      await _request('POST', '/recipes/$recipeId/optimize', token: token, body: {'mealType': mealType, 'futureMeal': futureMeal}) as Map<String, dynamic>;

  Future<Map<String, dynamic>> suggestedRecipes(String token, {String mealType = 'Lunch', String futureMeal = 'not_sure'}) async =>
      await _request('GET', '/recipes/suggested', token: token, query: {'mealType': mealType, 'futureMeal': futureMeal}) as Map<String, dynamic>;

  // --- Planned vs consumed meals (only "consume" counts as eaten) ---
  Future<Map<String, dynamic>> planMeal(String token, Map<String, dynamic> payload) async =>
      await _request('POST', '/meals/plan', token: token, body: payload) as Map<String, dynamic>;
  Future<Map<String, dynamic>> consumeMeal(String token, Map<String, dynamic> payload) async =>
      await _request('POST', '/meals/consume', token: token, body: payload) as Map<String, dynamic>;
  Future<Map<String, dynamic>> plannedMeals(String token) async =>
      await _request('GET', '/meals/planned', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> plannedMeal(String token, String id) async =>
      await _request('GET', '/meals/planned/$id', token: token) as Map<String, dynamic>;
  Future<void> deletePlannedMeal(String token, String id) async =>
      await _request('DELETE', '/meals/planned/$id', token: token);
  Future<Map<String, dynamic>> undoMeal(String token, String id) async =>
      await _request('POST', '/meals/$id/undo', token: token) as Map<String, dynamic>;
  Future<void> deleteMeal(String token, String id) async =>
      await _request('DELETE', '/meals/$id', token: token);

  // --- Daily nutrition + adherence ---
  Future<Map<String, dynamic>> nutritionSummary(String token) async =>
      await _request('GET', '/nutrition/summary', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> adherence(String token, int days) async =>
      await _request('GET', '/nutrition/adherence', token: token, query: {'days': '$days'}) as Map<String, dynamic>;

  // --- Grocery ---
  Future<Map<String, dynamic>> grocery(String token) async =>
      await _request('GET', '/grocery', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> addGroceryFromRecipe(String token, String recipeId) async =>
      await _request('POST', '/grocery/from-recipe/$recipeId', token: token) as Map<String, dynamic>;
  Future<void> clearGrocery(String token, String scope) async =>
      await _request('DELETE', '/grocery', token: token, query: {'scope': scope});
  Future<void> toggleGroceryItem(String token, String itemId, bool checked) async =>
      await _request('PATCH', '/grocery/$itemId', token: token, body: {'checked': checked});

  // --- Reminders ---
  Future<Map<String, dynamic>> reminders(String token) async =>
      await _request('GET', '/reminders', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> createReminder(String token, String title, String time) async =>
      await _request('POST', '/reminders', token: token, body: {'title': title, 'time': time}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> updateReminder(String token, String id, Map<String, dynamic> changes) async =>
      await _request('PUT', '/reminders/$id', token: token, body: changes) as Map<String, dynamic>;
  Future<void> deleteReminder(String token, String id) async =>
      await _request('DELETE', '/reminders/$id', token: token);
  Future<void> saveReminders(String token, List<Map<String, dynamic>> reminders) async =>
      await _request('POST', '/reminders/save', token: token, body: {'reminders': reminders});

  // --- Targets / progress ---
  Future<Map<String, dynamic>> myTarget(String token) async =>
      await _request('GET', '/targets/me', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> progressToday(String token) async =>
      await _request('GET', '/progress/today', token: token) as Map<String, dynamic>;

  // --- Coach ---
  Future<Map<String, dynamic>> coachDashboard(String token) async =>
      await _request('GET', '/coach/dashboard', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> coachClients(String token, {String? status, String? search}) async {
    final query = <String, String>{};
    if (status != null && status != 'All') query['status'] = status;
    if (search != null && search.isNotEmpty) query['search'] = search;
    return await _request('GET', '/coach/clients', token: token, query: query) as Map<String, dynamic>;
  }
  Future<Map<String, dynamic>> addClient(String token, String email) async =>
      await _request('POST', '/coach/clients', token: token, body: {'email': email}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> clientDetail(String token, String clientId) async =>
      await _request('GET', '/coach/clients/$clientId', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> setClientTargets(String token, String clientId, Map<String, dynamic> targets) async =>
      await _request('PUT', '/coach/clients/$clientId/targets', token: token, body: targets) as Map<String, dynamic>;
  Future<Map<String, dynamic>> clientProgress(String token, String clientId, {int days = 7}) async =>
      await _request('GET', '/coach/clients/$clientId/progress', token: token, query: {'days': '$days'}) as Map<String, dynamic>;

  // --- In-app notifications ---
  Future<Map<String, dynamic>> notifications(String token) async =>
      await _request('GET', '/notifications', token: token) as Map<String, dynamic>;
  Future<void> markNotificationsRead(String token, {List<String>? ids}) async =>
      await _request('POST', '/notifications/read', token: token, body: {'ids': ids});

  // --- Chat ---
  Future<Map<String, dynamic>> chatThread(String token, String clientId) async =>
      await _request('GET', '/messages/$clientId', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> sendChatMessage(String token, String clientId, String text) async =>
      await _request('POST', '/messages/$clientId', token: token, body: {'text': text}) as Map<String, dynamic>;
  Future<void> markChatRead(String token, String clientId) async =>
      await _request('POST', '/messages/$clientId/read', token: token);
  Future<Map<String, dynamic>> chatThreads(String token) async =>
      await _request('GET', '/messages/threads', token: token) as Map<String, dynamic>;
  Future<int> chatUnreadCount(String token) async {
    final data = await _request('GET', '/messages/unread-count', token: token) as Map<String, dynamic>;
    return (data['unread'] as num).toInt();
  }

  // --- Daily mission & camera-only meal photos ---
  Future<Map<String, dynamic>> missionToday(String token) async =>
      await _request('GET', '/missions/today', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> submitMealPhoto(String token, String mealLogId, List<int> bytes, DateTime capturedAt) async =>
      await _request('POST', '/missions/photo', token: token, body: {
        'mealLogId': mealLogId,
        'imageBase64': base64Encode(bytes),
        'source': 'camera', // the app has no gallery picker; the server rejects anything else
        'capturedAt': capturedAt.toUtc().toIso8601String(),
      }) as Map<String, dynamic>;

  // --- Profile, preferences, account ---
  Future<Map<String, dynamic>> updateProfile(String token, Map<String, dynamic> changes) async =>
      await _request('PATCH', '/auth/profile', token: token, body: changes) as Map<String, dynamic>;
  Future<Map<String, dynamic>> uploadAvatar(String token, List<int> bytes) async =>
      await _request('PUT', '/auth/avatar', token: token, body: {'imageBase64': base64Encode(bytes)}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> removeAvatar(String token) async =>
      await _request('DELETE', '/auth/avatar', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> getPreferences(String token) async =>
      await _request('GET', '/auth/preferences', token: token) as Map<String, dynamic>;
  Future<Map<String, dynamic>> updatePreferences(String token, Map<String, dynamic> changes) async =>
      await _request('PATCH', '/auth/preferences', token: token, body: changes) as Map<String, dynamic>;
  Future<Map<String, dynamic>> myCoach(String token) async =>
      await _request('GET', '/auth/my-coach', token: token) as Map<String, dynamic>;
  Future<void> deleteAccount(String token) async => await _request('DELETE', '/auth/me', token: token);

  // --- Online food search & custom food logging ---
  Future<Map<String, dynamic>> searchFoods(String token, String query) async =>
      await _request('GET', '/foods/search', token: token, query: {'q': query}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> logFood(String token, Map<String, dynamic> payload) async =>
      await _request('POST', '/foods/log', token: token, body: payload) as Map<String, dynamic>;

  // --- Online recipe search (imported into Firestore on the server) ---
  Future<Map<String, dynamic>> onlineRecipes(String token, String query) async =>
      await _request('GET', '/recipes/online', token: token, query: {'q': query}) as Map<String, dynamic>;
}
