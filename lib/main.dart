import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Settings Variables
  String _jsonFilename = "accounts.json";
  String _currentPassword = "";

  // FCM Variables
  String _fcmToken = "Fetching...";

  // Input Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cookiesController = TextEditingController();
  final TextEditingController _filenameController = TextEditingController();

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

    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

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

    final savedFilename = prefs.getString('json_filename');
    final savedPassword = prefs.getString('current_password');
    final savedToken = prefs.getString('fcm_token');

    setState(() {
      if (savedFilename != null) _jsonFilename = savedFilename;
      _currentPassword = savedPassword ?? "";
      if (savedToken != null) _fcmToken = savedToken;

      _filenameController.text = _jsonFilename;
      _passwordController.text = _currentPassword;

      String? accountsStr = prefs.getString('accounts_list');
      if (accountsStr != null && accountsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(accountsStr);
          _accounts =
              decoded.map((e) => Map<String, String>.from(e)).toList();
        } catch (e) {
          // ignore
        }
      }
    });

    if (_currentPassword.isEmpty) {
      _generatePassword();
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('json_filename', _jsonFilename);
    await prefs.setString('current_password', _currentPassword);
    await prefs.setString('accounts_list', json.encode(_accounts));
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Password copied"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  // --- Save (formerly Submit) ---
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
          return;
        }
        saveDir = Directory('${privateDir.path}/insta_saver');
      }

      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final File saveFile = File('${saveDir.path}/$_jsonFilename');
      await saveFile.writeAsString(fileContent);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Downloaded to ${saveFile.path}"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // ignore
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Imported ${_accounts.length} accounts"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // ignore
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
                  label: "Save",
                  isOutlined: false,
                  onPressed: _saveAccount,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Saved Card (shown after clicking Save)
          if (_lastSavedEntry != null) _buildSavedCard(_lastSavedEntry!),
        ],
      ),
    );
  }

  /// Card shown after saving — username | password | cookies + copy button
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
              cookies.isEmpty ? "—" : cookies,
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
        ? '${value.substring(0, 40)}…'
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

  /// Small button used next to Password field — with hover effect
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
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Reusable hover-aware container widget
// ─────────────────────────────────────────────────────────────────
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
