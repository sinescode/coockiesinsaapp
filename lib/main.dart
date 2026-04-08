import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'security_module.dart';

// Background message handler must be a top-level function
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

// Initialize Local Notifications Plugin globally for background handler
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Define the High Importance Channel
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'default_channel',
  'High Importance Notifications',
  description: 'This channel is used for important notifications.',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cookies Account Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xff0f172a),
        scaffoldBackgroundColor: const Color(0xff0f172a),
        cardColor: const Color(0xff111827),
        dividerColor: const Color(0xff1f2937),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xffe5e7eb)),
          bodySmall: TextStyle(color: Color(0xff94a3b8)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xff0b1220),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xff1f2937)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xff1f2937)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xff3b82f6)),
          ),
          labelStyle:
              const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff22c55e),
            foregroundColor: const Color(0xff0b1220),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xfff97316),
            side: const BorderSide(color: Color(0xfff97316)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // Data Models
  List<Map<String, String>> _accounts = [];
  List<Map<String, dynamic>> _logs = [];

  // Settings Variables
  String _webhook1Url = "http://43.135.182.151/api/api/v1/webhook/nRlmI2-8T7x2DAWe1hWxi97qGA1FcCxrNcyCtLTO_Cw/account-push";
  String _webhook2Url = "https://submitwork.org/api/push";
  int _activeWebhook = 1; // 1 = old direct system, 2 = new job_id system
  bool _webhookEnabled = true; // Toggle for webhook functionality

  String get _webhookUrl => _activeWebhook == 1 ? _webhook1Url : _webhook2Url;

  String _jsonFilename = "accounts.json";
  String _currentPassword = "";

  // FCM Variables
  String _fcmToken = "Fetching...";

  // Server Status Variables
  String _serverStatus = "Check";
  bool _isChecking = false;

  // Input Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cookiesController = TextEditingController();
  final TextEditingController _webhook1Controller = TextEditingController();
  final TextEditingController _webhook2Controller = TextEditingController();
  final TextEditingController _filenameController = TextEditingController();

  // Keep old single controller as alias for compatibility
  TextEditingController get _webhookController =>
      _activeWebhook == 1 ? _webhook1Controller : _webhook2Controller;

  // Last saved card data (for displaying after save)
  Map<String, String>? _lastSavedEntry;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initFCM();
  }

  // --- FCM Logic ---
  Future<void> _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
    } else {
      print('User declined or has not accepted permission');
    }

    String? token = await messaging.getToken();
    if (token != null) {
      setState(() {
        _fcmToken = token;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
    }

    messaging.onTokenRefresh.listen((newToken) {
      setState(() {
        _fcmToken = newToken;
      });
      _saveFCMToken(newToken);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: android.smallIcon,
              importance: Importance.high,
              priority: Priority.high,
              color: const Color(0xff22c55e),
            ),
          ),
        );
      }
    });
  }

  Future<void> _saveFCMToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
  }

  // --- Data Persistence Logic ---

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedWebhook1 = prefs.getString('webhook1_url');
    final savedWebhook2 = prefs.getString('webhook2_url');
    final savedActiveWebhook = prefs.getInt('active_webhook');
    final savedWebhookEnabled = prefs.getBool('webhook_enabled');
    final savedFilename = prefs.getString('json_filename');
    final savedPassword = prefs.getString('current_password');
    final savedToken = prefs.getString('fcm_token');

    setState(() {
      if (savedWebhook1 != null) _webhook1Url = savedWebhook1;
      if (savedWebhook2 != null) _webhook2Url = savedWebhook2;
      if (savedActiveWebhook != null) _activeWebhook = savedActiveWebhook;
      if (savedWebhookEnabled != null) _webhookEnabled = savedWebhookEnabled;
      if (savedFilename != null) _jsonFilename = savedFilename;
      _currentPassword = savedPassword ?? "";
      if (savedToken != null) _fcmToken = savedToken;

      _webhook1Controller.text = _webhook1Url;
      _webhook2Controller.text = _webhook2Url;
      _filenameController.text = _jsonFilename;
      _passwordController.text = _currentPassword;

      String? accountsStr = prefs.getString('accounts_list');
      if (accountsStr != null && accountsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(accountsStr);
          _accounts =
              decoded.map((e) => Map<String, String>.from(e)).toList();
        } catch (e) {
          _addLog("System", "Error loading saved accounts: $e");
        }
      }

      String? logsStr = prefs.getString('logs_list');
      if (logsStr != null && logsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(logsStr);
          _logs =
              decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (e) {
          print("Error loading logs: $e");
        }
      }
    });

    if (_currentPassword.isEmpty) {
      _generatePassword();
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webhook1_url', _webhook1Url);
    await prefs.setString('webhook2_url', _webhook2Url);
    await prefs.setInt('active_webhook', _activeWebhook);
    await prefs.setBool('webhook_enabled', _webhookEnabled);
    await prefs.setString('json_filename', _jsonFilename);
    await prefs.setString('current_password', _currentPassword);
    await prefs.setString('accounts_list', json.encode(_accounts));
    await prefs.setString('logs_list', json.encode(_logs));
  }

  // --- Feature Logic ---

  void _generatePassword() {
    const chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    final dateStr = DateFormat('dd').format(DateTime.now());
    final random = Random();
    final length = random.nextInt(5) + 8;
    final letterCount = length - dateStr.length;

    String result = '';
    for (int i = 0; i < letterCount; i++) {
      result += chars[random.nextInt(chars.length)];
    }

    setState(() {
      _currentPassword = result + dateStr;
      _passwordController.text = _currentPassword;
    });
    _saveData();
  }

  void _copyPassword() {
    Clipboard.setData(ClipboardData(text: _currentPassword));
    if (_webhookEnabled) {
      _addLog("System", "Password copied successfully");
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Password copied"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Retry helper â€” retries up to 3 times on failure/5xx
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<http.Response?> _postWithRetry(String url, String body,
      {int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'text/plain'},
              body: body,
            )
            .timeout(const Duration(seconds: 12));

        // Retry on 5xx server errors
        if (response.statusCode >= 500) {
          if (i < retries - 1) {
            await Future.delayed(Duration(seconds: 2 * (i + 1)));
            continue;
          }
        }
        return response;
      } on TimeoutException {
        if (i < retries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
          continue;
        }
        return null;
      } catch (e) {
        if (i < retries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
          continue;
        }
        return null;
      }
    }
    return null;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Poll job status â€” handles TimeoutException gracefully
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _pollJobStatus(String jobId) async {
    final statusUrl =
        Uri.parse("https://submitwork.org/api/status/$jobId");

    for (int i = 0; i < 20; i++) {
      // max ~60 seconds total
      await Future.delayed(const Duration(seconds: 3));

      try {
        final res = await http
            .get(statusUrl)
            .timeout(const Duration(seconds: 12));

        // Server blip â€” keep polling
        if (res.statusCode >= 500) continue;

        if (res.statusCode != 200) {
          _addLog("Error", "Status check failed: HTTP ${res.statusCode}");
          return;
        }

        dynamic data;
        try {
          data = jsonDecode(res.body);
        } catch (_) {
          // Bad JSON on this attempt â€” retry
          continue;
        }

        final String status = data['status'] ?? '';

        if (status == 'done') {
          final int success = (data['data']?['success_count'] ?? 0) as int;
          final int failed = (data['data']?['failed_count'] ?? 0) as int;
          final List errors = data['errors'] ?? [];

          String logMsg = "âœ“ Success: $success | âœ— Failed: $failed";
          if (errors.isNotEmpty) logMsg += " | ${errors.first}";

          _addLog(
            success > 0 ? "Webhook" : "Error",
            logMsg,
            style: success > 0 ? "bold" : "normal",
          );
          return;
        }
        // status == 'processing' or other â€” keep polling

      } on TimeoutException {
        // Don't abort â€” just retry next iteration
        continue;
      } catch (e) {
        _addLog("Error", "Poll error: $e");
        return;
      }
    }

    _addLog("Error", "Timeout: job $jobId did not complete in time");
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Check server status â€” accepts any 2xx status code (202, 200, 201 all valid)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _checkServerStatus() async {
    final url = _webhookUrl;
    if (url.isEmpty || !url.startsWith("http")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please set a valid Webhook URL in Settings first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isChecking = true;
      _serverStatus = "Checking...";
    });

    const chars = "abcdefghijklmnopqrstuvwxyz1234567890";
    final random = Random();

    String randomUser =
        List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
    String randomPass =
        List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
    String randomCookie =
        List.generate(10, (_) => chars[random.nextInt(chars.length)]).join();

    String convertedStr = "$randomUser:$randomPass|||$randomCookie||";
    String payload =
        "accounts=${base64.encode(utf8.encode(convertedStr))}";

    try {
      final response = await _postWithRetry(url, payload);

      if (response == null) {
        setState(() => _serverStatus = "OFF");
        return;
      }

      // Accept any 2xx (200, 201, 202) â€” was only accepting 200 before
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.body.isEmpty) {
        setState(() => _serverStatus = "OFF");
        return;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        setState(() => _serverStatus = "OFF");
        return;
      }

      if (_activeWebhook == 2) {
        // New system: ON if response has a job_id
        final String? jobId = decoded['job_id'];
        setState(() => _serverStatus =
            (jobId != null && jobId.isNotEmpty) ? "ON" : "OFF");
      } else {
        // Old system: ON if success_count or failed_count present
        if (decoded is List && decoded.isNotEmpty) decoded = decoded[0];
        if (decoded is Map) {
          dynamic dataNode =
              decoded['data'] is Map ? decoded['data'] : decoded;
          int successCount = dataNode['success_count'] ?? 0;
          int failedCount = dataNode['failed_count'] ?? 0;
          setState(() => _serverStatus =
              (successCount > 0 || failedCount > 0) ? "ON" : "OFF");
        } else {
          setState(() => _serverStatus = "OFF");
        }
      }
    } catch (e) {
      setState(() => _serverStatus = "OFF");
    } finally {
      setState(() => _isChecking = false);
    }
  }

  // --- Submit: routes to old or new system based on active webhook ---
  Future<void> _submitData() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final cookies = _cookiesController.text.trim();

    _currentPassword = password;
    _jsonFilename = _filenameController.text.trim();
    if (_activeWebhook == 1) {
      _webhook1Url = _webhook1Controller.text.trim();
    } else {
      _webhook2Url = _webhook2Controller.text.trim();
    }

    if (username.isEmpty || password.isEmpty) {
      if (_webhookEnabled) {
        _addLog("Error", "Username and Password required");
      }
      return;
    }

    final newEntry = {
      "email": "",
      "username": username,
      "password": password,
      "auth_code": cookies,
    };

    setState(() {
      _accounts.insert(0, newEntry);
      _lastSavedEntry = newEntry;
    });

    await _saveData();

    // If webhook is disabled, just save and clear inputs
    if (!_webhookEnabled) {
      _usernameController.clear();
      _cookiesController.clear();
      _generatePassword();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Account saved successfully (Webhook OFF)"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    String convertedStr = "$username:$password|||$cookies||";
    String payload =
        "accounts=${base64.encode(utf8.encode(convertedStr))}";

    if (_activeWebhook == 2) {
      // --- New system: job_id polling ---
      final pushResponse = await _postWithRetry(_webhook2Url, payload);

      if (pushResponse == null) {
        _addLog("Error", "Server unreachable after 3 attempts");
        _usernameController.clear();
        _cookiesController.clear();
        _generatePassword();
        return;
      }

      if (pushResponse.body.isEmpty) {
        _addLog("Error", "(${pushResponse.statusCode}) Empty response");
        _usernameController.clear();
        _cookiesController.clear();
        _generatePassword();
        return;
      }

      dynamic pushJson;
      try {
        pushJson = jsonDecode(pushResponse.body);
      } catch (_) {
        _addLog("Error",
            "(${pushResponse.statusCode}) Invalid JSON: ${pushResponse.body}");
        _usernameController.clear();
        _cookiesController.clear();
        _generatePassword();
        return;
      }

      final String? jobId = pushJson['job_id'];
      if (jobId == null) {
        final msg = pushJson['message'] ?? pushResponse.body;
        _addLog("Error", "(${pushResponse.statusCode}) $msg");
        _usernameController.clear();
        _cookiesController.clear();
        _generatePassword();
        return;
      }

      _addLog("Webhook", "Job submitted [$jobId] â€” waiting for result...");
      await _pollJobStatus(jobId);
    } else {
      // --- Old system: direct success_count/failed_count response ---
      try {
        final response = await http.post(
          Uri.parse(_webhook1Url),
          headers: {'Content-Type': 'text/plain'},
          body: payload,
        );

        String logMessage = "Empty response";
        String logStatus = (response.statusCode >= 200 &&
                response.statusCode < 300)
            ? "Webhook"
            : "Error";

        if (response.body.isNotEmpty) {
          try {
            dynamic decoded = jsonDecode(response.body);
            if (decoded is List && decoded.isNotEmpty) decoded = decoded[0];

            if (decoded is Map) {
              dynamic dataNode =
                  decoded['data'] is Map ? decoded['data'] : decoded;
              int successCount = dataNode['success_count'] ?? 0;
              int failedCount = dataNode['failed_count'] ?? 0;

              logMessage = "âœ“ Success: $successCount | âœ— Failed: $failedCount";

              String logStyle = "normal";
              if (successCount == 0) {
                logStatus = "Error";
              } else if (failedCount == 0) {
                logStyle = "bold";
              }

              _addLog(logStatus, "(${response.statusCode}) $logMessage",
                  style: logStyle);
            } else {
              logMessage = response.body.trim();
              _addLog(logStatus, "(${response.statusCode}) $logMessage");
            }
          } catch (e) {
            logMessage = "Invalid JSON response";
            _addLog(logStatus, "(${response.statusCode}) $logMessage");
          }
        } else {
          _addLog(logStatus, "(${response.statusCode}) $logMessage");
        }
      } catch (e) {
        _addLog("Error", "Connection error: $e");
      }
    }

    _usernameController.clear();
    _cookiesController.clear();
    _generatePassword();
  }

  // --- Save (formerly Submit) - for non-webhook mode ---
  Future<void> _saveAccount() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final cookies = _cookiesController.text.trim();

    _currentPassword = password;
    _jsonFilename = _filenameController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Username and Password are required"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newEntry = {
      "email": "",
      "username": username,
      "password": password,
      "auth_code": cookies,
    };

    setState(() {
      _accounts.insert(0, newEntry);
      _lastSavedEntry = newEntry;
    });

    await _saveData();

    _usernameController.clear();
    _cookiesController.clear();
    _generatePassword();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Account saved successfully"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _addLog(String status, String message, {String style = "normal"}) {
    setState(() {
      _logs.insert(0, {
        "status": status,
        "message": message,
        "time": DateFormat.Hms().format(DateTime.now()),
        "style": style,
      });
    });
    _saveData();
  }

  // --- DOWNLOAD ENCRYPTED FILE ---
  Future<void> _downloadEncryptedFile() async {
    try {
      final String activePassword =
          _passwordController.text.trim().isNotEmpty
              ? _passwordController.text.trim()
              : _currentPassword;

      final String rawJson = json.encode(_accounts);
      final String encryptedOutput =
          SecureVault.pack(rawJson, activePassword);
      final String fileContent = '$activePassword\n$encryptedOutput';

      if (!Platform.isAndroid) {
        if (_webhookEnabled) {
          _addLog("Error", "Download only supported on Android");
        }
        return;
      }

      var permission = await Permission.manageExternalStorage.status;
      if (!permission.isGranted) {
        permission = await Permission.manageExternalStorage.request();
      }

      Directory saveDir;
      if (permission.isGranted) {
        saveDir = Directory('/storage/emulated/0/Download/insta_saver');
      } else {
        final Directory? privateDir = await getDownloadsDirectory();
        if (privateDir == null) {
          if (_webhookEnabled) {
            _addLog("Error", "Cannot access Downloads directory");
          }
          return;
        }
        saveDir = Directory('${privateDir.path}/insta_saver');
      }

      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final File saveFile = File('${saveDir.path}/$_jsonFilename');
      await saveFile.writeAsString(fileContent);

      if (_webhookEnabled) {
        _addLog("System", "File saved to ${saveFile.path}");
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Downloaded to ${saveFile.path}"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (_webhookEnabled) {
        _addLog("Error", "Download failed: $e");
      }
    }
  }

  // --- ENCRYPTED IMPORT ---
  Future<void> _importFromFile() async {
    if (!Platform.isAndroid) return;

    try {
      var permission = await Permission.manageExternalStorage.status;
      if (!permission.isGranted) {
        permission = await Permission.manageExternalStorage.request();
      }

      Directory saveDir;
      if (permission.isGranted) {
        saveDir = Directory('/storage/emulated/0/Download/insta_saver');
      } else {
        final Directory? privateDir = await getDownloadsDirectory();
        if (privateDir == null) return;
        saveDir = Directory('${privateDir.path}/insta_saver');
      }

      final File file = File('${saveDir.path}/$_jsonFilename');

      if (!await file.exists()) {
        if (_webhookEnabled) {
          _addLog("Error", "No backup file found at ${file.path}");
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No backup file found at ${file.path}"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      String fileContent = await file.readAsString();
      final int newlineIdx = fileContent.indexOf('\n');
      String encryptedContent;
      String filePassword;

      if (newlineIdx != -1) {
        filePassword = fileContent.substring(0, newlineIdx).trim();
        encryptedContent = fileContent.substring(newlineIdx + 1).trim();
      } else {
        filePassword = _passwordController.text.trim().isNotEmpty
            ? _passwordController.text.trim()
            : _currentPassword;
        encryptedContent = fileContent;
      }

      String decryptedJson =
          SecureVault.unpack(encryptedContent, filePassword);

      if (decryptedJson.startsWith("ERROR:")) {
        if (_webhookEnabled) {
          _addLog(
              "Error", "Decryption Failed: Wrong password or tampered file");
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Import Failed: Wrong Password?"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final List<dynamic> decoded = json.decode(decryptedJson);
      setState(() {
        _accounts =
            decoded.map((e) => Map<String, String>.from(e)).toList();
      });

      await _saveData();
      if (_webhookEnabled) {
        _addLog(
            "Success", "Imported ${_accounts.length} accounts from secure backup");
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Imported ${_accounts.length} accounts"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (_webhookEnabled) {
        _addLog("Error", "Import failed: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Account Manager",
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xff111827),
        elevation: 0,
        actions: [
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _serverStatus == "ON"
                    ? Colors.green.withOpacity(0.2)
                    : _serverStatus == "OFF"
                        ? Colors.red.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _serverStatus,
                style: TextStyle(
                  color: _serverStatus == "ON"
                      ? Colors.greenAccent
                      : _serverStatus == "OFF"
                          ? Colors.redAccent
                          : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          _isChecking
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _checkServerStatus,
                  tooltip: "Check Server Status",
                ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildSavedTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xff111827),
        selectedItemColor: const Color(0xff22c55e),
        unselectedItemColor: const Color(0xff94a3b8),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.save_alt), label: "Saved"),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: "Settings"),
        ],
      ),
    );
  }

  // --- TAB 1: HOME ---

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInput("Username", _usernameController, false),
          const SizedBox(height: 15),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Password",
                  style:
                      TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _passwordController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xff0b1220),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Color(0xff1f2937)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  _buildSmallBtn("Copy", _copyPassword),
                  const SizedBox(width: 5),
                  _buildSmallBtn("Change", _generatePassword),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),

          _buildInput("Cookies", _cookiesController, false),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _buildHoverButton(
                  label: "Clear Inputs",
                  isOutlined: true,
                  onPressed: () {
                    _usernameController.clear();
                    _cookiesController.clear();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _buildHoverButton(
                  label: _webhookEnabled ? "Convert & Push" : "Save",
                  isOutlined: false,
                  onPressed: _webhookEnabled ? _submitData : _saveAccount,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Logs Section - Only show if webhook is enabled
          if (_webhookEnabled) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Logs",
                    style: TextStyle(
                        color: Color(0xff94a3b8),
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {
                    setState(() => _logs.clear());
                    _saveData();
                  },
                  child: const Text("Clear Logs",
                      style:
                          TextStyle(fontSize: 12, color: Colors.red)),
                )
              ],
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: const Color(0xff0b1220),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xff1f2937)),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text("No logs yet",
                          style: TextStyle(
                              color: Color(0xff475569), fontSize: 12)))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final isError = log['status'] == "Error" ||
                            log['status'] == "Warning";
                        final isWebhook = log['status'] == "Webhook";
                        final isBold = log['style'] == "bold";

                        Color logColor;
                        if (isError) {
                          logColor = Colors.redAccent;
                        } else if (isWebhook) {
                          logColor = Colors.cyanAccent;
                        } else {
                          logColor = Colors.greenAccent;
                        }

                        FontWeight fontWeight =
                            isBold ? FontWeight.bold : FontWeight.normal;

                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                          leading: Text(
                            log['time'],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Color(0xff94a3b8),
                            ),
                          ),
                          title: Text(
                            "${log['status']}: ${log['message']}",
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: logColor,
                              fontWeight: fontWeight,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],

          const SizedBox(height: 30),

          // Saved Card (shown after clicking Save) - Only show if webhook is disabled
          if (!_webhookEnabled && _lastSavedEntry != null) _buildSavedCard(_lastSavedEntry!),
        ],
      ),
    );
  }

  /// Card shown after saving â€” username | password | cookies + copy button
  Widget _buildSavedCard(Map<String, String> entry) {
    final username = entry['username'] ?? '';
    final password = entry['password'] ?? '';
    final cookies = entry['auth_code'] ?? '';
    final cardText = "$username|$password|$cookies";

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xff22c55e).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: Color(0xff22c55e), size: 16),
              const SizedBox(width: 6),
              const Text(
                "Saved",
                style: TextStyle(
                  color: Color(0xff22c55e),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Copy card button
              _buildHoverIconButton(
                icon: Icons.copy,
                color: const Color(0xff94a3b8),
                tooltip: "Copy username|password|cookies",
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cardText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Copied to clipboard"),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              // Close card button
              _buildHoverIconButton(
                icon: Icons.close,
                color: Colors.red,
                tooltip: "Dismiss",
                onPressed: () => setState(() => _lastSavedEntry = null),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Username row
          _buildCardRow(Icons.person, "Username", username),
          const SizedBox(height: 6),
          // Password row
          _buildCardRow(Icons.lock, "Password", password),
          const SizedBox(height: 6),
          // Cookies row
          _buildCardRow(Icons.cookie, "Cookies",
              cookies.isEmpty ? "â€”" : cookies,
              truncate: true),
          const SizedBox(height: 14),
          // Formatted copy button
          SizedBox(
            width: double.infinity,
            child: _buildHoverButton(
              label: "Copy  username|password|cookies",
              isOutlined: true,
              icon: Icons.copy,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: cardText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Copied to clipboard"),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardRow(IconData icon, String label, String value,
      {bool truncate = false}) {
    final display = (truncate && value.length > 40)
        ? '${value.substring(0, 40)}â€¦'
        : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xff94a3b8)),
        const SizedBox(width: 6),
        Text(
          "$label: ",
          style: const TextStyle(
              color: Color(0xff94a3b8), fontSize: 12),
        ),
        Expanded(
          child: Text(
            display,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInput(
      String label, TextEditingController controller, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  /// Small button used next to Password field â€” with hover effect
  Widget _buildSmallBtn(String text, VoidCallback onTap) {
    return _HoverContainer(
      onTap: onTap,
      defaultColor: const Color(0xff334155),
      hoverColor: const Color(0xff475569),
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  /// Full-width outlined / filled button with hover effect
  Widget _buildHoverButton({
    required String label,
    required bool isOutlined,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    return _HoverContainer(
      onTap: onPressed,
      defaultColor: isOutlined
          ? Colors.transparent
          : const Color(0xff22c55e),
      hoverColor: isOutlined
          ? const Color(0xfff97316).withOpacity(0.12)
          : const Color(0xff16a34a),
      borderRadius: 8,
      border: isOutlined
          ? Border.all(color: const Color(0xfff97316))
          : null,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 15,
                color: isOutlined
                    ? const Color(0xfff97316)
                    : const Color(0xff0b1220)),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: isOutlined
                  ? const Color(0xfff97316)
                  : const Color(0xff0b1220),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Icon button with hover highlight
  Widget _buildHoverIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? tooltip,
    double size = 18,
    double padding = 4,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: _HoverContainer(
        onTap: onPressed,
        defaultColor: Colors.transparent,
        hoverColor: color.withOpacity(0.18),
        borderRadius: 8,
        padding: EdgeInsets.all(padding),
        child: Icon(icon, color: color, size: size),
      ),
    );
  }

  /// Dialog action button with hover effect
  Widget _buildDialogBtn(String label, Color textColor, VoidCallback onTap) {
    return _HoverContainer(
      onTap: onTap,
      defaultColor: Colors.transparent,
      hoverColor: textColor.withOpacity(0.12),
      borderRadius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  // --- TAB 2: SAVED ---

  Widget _buildSavedTab() {
    final Map<String, int> usernameCounts = {};
    for (var acc in _accounts) {
      final user = acc['username'] ?? "";
      if (user.isNotEmpty) {
        usernameCounts[user] = (usernameCounts[user] ?? 0) + 1;
      }
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xff111827),
            border: Border(
                bottom: BorderSide(color: Color(0xff1f2937))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Saved Accounts: ${_accounts.length}",
                  style: const TextStyle(color: Colors.white)),
              Row(
                children: [
                  _buildHoverIconButton(
                    icon: Icons.download,
                    color: const Color(0xff22c55e),
                    tooltip: "Download Backup",
                    onPressed: _downloadEncryptedFile,
                    size: 26,
                    padding: 8,
                  ),
                  const SizedBox(width: 12),
                  _buildHoverIconButton(
                    icon: Icons.delete_sweep,
                    color: Colors.red,
                    tooltip: "Clear All",
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xff1f2937),
                          title: const Text("Delete All Accounts",
                              style:
                                  TextStyle(color: Colors.white)),
                          content: const Text(
                            "Are you sure you want to delete ALL saved accounts?",
                            style:
                                TextStyle(color: Color(0xffe5e7eb)),
                          ),
                          actions: [
                            _buildDialogBtn("Cancel", const Color(0xff94a3b8),
                                () => Navigator.pop(context, false)),
                            _buildDialogBtn("Delete All", Colors.redAccent,
                                () => Navigator.pop(context, true)),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        setState(() => _accounts.clear());
                        _saveData();
                        if (_webhookEnabled) {
                          _addLog("System", "All accounts cleared");
                        }
                      }
                    },
                    size: 26,
                    padding: 8,
                  ),
                ],
              )
            ],
          ),
        ),
        Expanded(
          child: _accounts.isEmpty
              ? const Center(
                  child: Text("No saved accounts",
                      style:
                          TextStyle(color: Color(0xff475569))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _accounts.length,
                  itemBuilder: (context, index) {
                    final acc = _accounts[index];
                    final currentUsername = acc['username'] ?? "";
                    final bool isDuplicate =
                        (usernameCounts[currentUsername] ?? 0) > 1;
                    final Color cardColor = isDuplicate
                        ? const Color(0xff7f1d1d)
                        : const Color(0xff1f2937);

                    final username = acc['username'] ?? '';
                    final password = acc['password'] ?? '';
                    final cookies = acc['auth_code'] ?? '';
                    final copyText = "$username|$password|$cookies";

                    return Card(
                      color: cardColor,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      if (isDuplicate)
                                        const Icon(
                                            Icons
                                                .warning_amber_rounded,
                                            color:
                                                Colors.orangeAccent,
                                            size: 18),
                                      if (isDuplicate)
                                        const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          currentUsername,
                                          style: const TextStyle(
                                            fontWeight:
                                                FontWeight.bold,
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    // Copy button per card
                                    _buildHoverIconButton(
                                      icon: Icons.copy,
                                      color: const Color(0xff94a3b8),
                                      tooltip: "Copy username|password|cookies",
                                      onPressed: () {
                                        Clipboard.setData(
                                            ClipboardData(text: copyText));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content:
                                                Text("Copied to clipboard"),
                                            backgroundColor: Colors.green,
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      },
                                    ),
                                    _buildHoverIconButton(
                                      icon: Icons.close,
                                      color: Colors.red,
                                      tooltip: "Delete",
                                      onPressed: () async {
                                        final confirm =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (context) =>
                                              AlertDialog(
                                            backgroundColor:
                                                const Color(0xff1f2937),
                                            title: const Text(
                                                "Delete Account",
                                                style: TextStyle(
                                                    color: Colors.white)),
                                            content: const Text(
                                                "Are you sure?",
                                                style: TextStyle(
                                                    color: Color(
                                                        0xffe5e7eb))),
                                            actions: [
                                              _buildDialogBtn("Cancel", const Color(0xff94a3b8),
                                                  () => Navigator.pop(context, false)),
                                              _buildDialogBtn("Delete", Colors.redAccent,
                                                  () => Navigator.pop(context, true)),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          setState(() =>
                                              _accounts.removeAt(index));
                                          _saveData();
                                          if (_webhookEnabled) {
                                            _addLog(
                                                "System", "Account deleted");
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Password: $password",
                              style: const TextStyle(
                                  color: Color(0xff94a3b8),
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Cookies: ${cookies.isEmpty ? 'None' : '${cookies.substring(0, cookies.length < 30 ? cookies.length : 30)}...'}",
                              style: const TextStyle(
                                  color: Color(0xff94a3b8),
                                  fontSize: 11),
                            ),
                            const SizedBox(height: 10),
                            // Copy format button
                            SizedBox(
                              width: double.infinity,
                              child: _buildHoverButton(
                                label: "Copy  $username|$password|...",
                                isOutlined: true,
                                icon: Icons.copy,
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: copyText));
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text("Copied to clipboard"),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- TAB 3: SETTINGS ---

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FCM Device Token
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff1f2937)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("FCM Device Token",
                        style: TextStyle(
                            color: Color(0xff94a3b8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    _buildHoverIconButton(
                      icon: Icons.copy,
                      color: const Color(0xff94a3b8),
                      tooltip: "Copy token",
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _fcmToken));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Token copied to clipboard"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _fcmToken,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Webhook Toggle Switch
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff1f2937)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Webhook Enabled",
                          style: TextStyle(
                              color: Color(0xff94a3b8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        _webhookEnabled
                            ? "Logs will show in Home tab"
                            : "Logs hidden in Home tab",
                        style: const TextStyle(
                            color: Color(0xff475569), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _webhookEnabled,
                  onChanged: (value) {
                    setState(() {
                      _webhookEnabled = value;
                    });
                    _saveData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _webhookEnabled
                              ? "Webhook enabled - Logs visible"
                              : "Webhook disabled - Logs hidden",
                        ),
                        backgroundColor:
                            _webhookEnabled ? Colors.green : Colors.orange,
                      ),
                    );
                  },
                  activeColor: const Color(0xff22c55e),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Active Webhook Selector (only show if webhook is enabled)
          if (_webhookEnabled) ...[
            const Text("Active Webhook",
                style: TextStyle(
                    color: Color(0xff94a3b8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xff111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xff1f2937)),
              ),
              child: Column(
                children: [
                  _buildWebhookRadio(
                    value: 1,
                    label: "Webhook 1 â€” Direct System",
                    subtitle: "Parses success/failed counts instantly",
                    color: const Color(0xff22c55e),
                  ),
                  Divider(height: 1, color: const Color(0xff1f2937)),
                  _buildWebhookRadio(
                    value: 2,
                    label: "Webhook 2 â€” Job ID System",
                    subtitle: "submitwork.org async job_id API",
                    color: const Color(0xff3b82f6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Webhook 1 URL
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xff22c55e),
                    shape: BoxShape.circle,
                  ),
                ),
                const Text("Webhook 1 URL (Direct)",
                    style: TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _webhook1Controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: _activeWebhook == 1
                    ? const Icon(Icons.check_circle,
                        color: Color(0xff22c55e), size: 18)
                    : null,
              ),
            ),
            const SizedBox(height: 20),

            // Webhook 2 URL
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xff3b82f6),
                    shape: BoxShape.circle,
                  ),
                ),
                const Text("Webhook 2 URL (Job ID)",
                    style: TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _webhook2Controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: _activeWebhook == 2
                    ? const Icon(Icons.check_circle,
                        color: Color(0xff3b82f6), size: 18)
                    : null,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // JSON Filename
          TextField(
            controller: _filenameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: "JSON Filename",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            child: _buildHoverButton(
              label: "Save Settings",
              isOutlined: true,
              onPressed: () {
                setState(() {
                  _webhook1Url = _webhook1Controller.text.trim();
                  _webhook2Url = _webhook2Controller.text.trim();
                  _jsonFilename = _filenameController.text.trim();
                });
                _saveData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Settings Saved"),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildWebhookRadio({
    required int value,
    required String label,
    required String subtitle,
    required Color color,
  }) {
    final bool isSelected = _activeWebhook == value;
    return _HoverContainer(
      onTap: () => setState(() => _activeWebhook = value),
      defaultColor: Colors.transparent,
      hoverColor: color.withOpacity(0.1),
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Radio<int>(
            value: value,
            groupValue: _activeWebhook,
            onChanged: (v) => setState(() => _activeWebhook = v!),
            activeColor: color,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xff94a3b8),
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: Color(0xff475569), fontSize: 11),
                ),
              ],
            ),
          ),
          if (isSelected)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "ACTIVE",
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Reusable hover-aware container widget
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _HoverContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color defaultColor;
  final Color hoverColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;

  const _HoverContainer({
    required this.child,
    required this.onTap,
    required this.defaultColor,
    required this.hoverColor,
    required this.borderRadius,
    required this.padding,
    this.border,
  });

  @override
  State<_HoverContainer> createState() => _HoverContainerState();
}

class _HoverContainerState extends State<_HoverContainer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverColor : widget.defaultColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: widget.border,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}