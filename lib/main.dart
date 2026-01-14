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

void main() {
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
        primaryColor: const Color(0xff0f172a), // Slate 900
        scaffoldBackgroundColor: const Color(0xff0f172a),
        cardColor: const Color(0xff111827), // Slate 950
        dividerColor: const Color(0xff1f2937),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xffe5e7eb)), // Slate 200
          bodySmall: TextStyle(color: Color(0xff94a3b8)),  // Slate 400
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
          labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff22c55e), // Green 500
            foregroundColor: const Color(0xff0b1220),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xfff97316), // Orange 500
            side: const BorderSide(color: Color(0xfff97316)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
  List<Map<String, dynamic>> _accounts = []; // Changed to dynamic
  List<Map<String, dynamic>> _logs = [];
  
  // Settings
  String _webhookUrl = "https://ins.skysysx.com/api/api/v1/webhook/...";
  String _jsonFilename = "accounts.json";
  String _currentPassword = "";
  
  // Input Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cookiesController = TextEditingController();
  final TextEditingController _webhookController = TextEditingController();
  final TextEditingController _filenameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- Fixed Data Persistence Logic ---
  
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load settings FIRST
    final savedWebhook = prefs.getString('webhook_url');
    final savedFilename = prefs.getString('json_filename');
    final savedPassword = prefs.getString('current_password');
    
    setState(() {
      // Only use defaults if nothing saved
      _webhookUrl = savedWebhook ?? _webhookUrl;
      _jsonFilename = savedFilename ?? _jsonFilename;
      _currentPassword = savedPassword ?? "";
      
      // Load Accounts with proper type conversion
      String? accountsStr = prefs.getString('accounts_list');
      if (accountsStr != null && accountsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(accountsStr);
          _accounts = decoded.map<Map<String, dynamic>>((item) {
            return Map<String, dynamic>.from(item);
          }).toList();
        } catch (e) {
          _addLog("Error", "Failed to load accounts: $e");
        }
      }

      // Load Logs
      String? logsStr = prefs.getString('logs_list');
      if (logsStr != null && logsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(logsStr);
          _logs = decoded.map<Map<String, dynamic>>((item) {
            return Map<String, dynamic>.from(item);
          }).toList();
        } catch (e) {
          _addLog("Error", "Failed to load logs: $e");
        }
      }
      
      // Set controllers AFTER loading data
      _webhookController.text = _webhookUrl;
      _filenameController.text = _jsonFilename;
      _passwordController.text = _currentPassword;
      
      // Generate new password ONLY if no password exists
      if (_currentPassword.isEmpty) {
        _generatePassword();
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webhook_url', _webhookUrl);
    await prefs.setString('json_filename', _jsonFilename);
    await prefs.setString('current_password', _currentPassword);
    
    // Save accounts with proper encoding
    await prefs.setString('accounts_list', json.encode(_accounts));
    await prefs.setString('logs_list', json.encode(_logs));
  }

  // --- Fixed Feature Logic ---

  void _generatePassword() {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#";
    final dateStr = DateFormat('dd').format(DateTime.now());
    final random = Random();
    final length = random.nextInt(5) + 8;
    final letterCount = length - dateStr.length;

    String result = '';
    for (int i = 0; i < letterCount; i++) {
      result += chars[random.nextInt(chars.length)];
    }
    _currentPassword = result + dateStr;
    _passwordController.text = _currentPassword;
    _saveData(); // Save immediately
  }

  // --- FIXED Storage Export Function ---
  
  Future<void> _exportToFile() async {
    if (_accounts.isEmpty) {
      _addLog("Error", "No accounts to export");
      return;
    }

    try {
      // Use getExternalStorageDirectory for Android Download folder
      Directory? directory;
      
      if (Platform.isAndroid) {
        // For Android, use external storage directory
        directory = await getExternalStorageDirectory();
        if (directory != null) {
          // Navigate to Download subdirectory
          directory = Directory('${directory.path}/Download/insta_saver');
        }
      } else if (Platform.isIOS) {
        // For iOS, use documents directory
        directory = await getApplicationDocumentsDirectory();
      }
      
      if (directory == null) {
        _addLog("Error", "Could not access storage directory");
        return;
      }

      // Create directory if it doesn't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final file = File('${directory.path}/$_jsonFilename');
      final jsonData = json.encode(_accounts, toEncodable: (dynamic item) {
        if (item is Map<String, dynamic>) {
          return item.map((key, value) => MapEntry(key, value.toString()));
        }
        return item.toString();
      });
      
      await file.writeAsString(jsonData);
      
      _addLog("Success", "Exported ${_accounts.length} accounts to: ${file.path}");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Exported to ${file.path}"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      _addLog("Error", "Export failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Export failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- Fixed Saved Tab with Better Cards ---

  Widget _buildSavedTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xff111827),
            border: Border(bottom: BorderSide(color: Color(0xff1f2937)))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Saved Accounts: ${_accounts.length}",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _exportToFile,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text("Export"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff22c55e),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _accounts.isEmpty ? null : () {
                      _showClearConfirmationDialog();
                    },
                    icon: const Icon(Icons.delete_forever, size: 18, color: Colors.white),
                    label: const Text("Clear All", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
        Expanded(
          child: _accounts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save_alt, size: 64, color: Color(0xff475569)),
                      SizedBox(height: 16),
                      Text("No saved accounts yet", 
                          style: TextStyle(color: Color(0xff94a3b8), fontSize: 16)),
                      SizedBox(height: 8),
                      Text("Add accounts from the Home tab", 
                          style: TextStyle(color: Color(0xff64748b), fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _accounts.length,
                  itemBuilder: (context, index) {
                    final acc = _accounts[index];
                    return _buildAccountCard(acc, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account, int index) {
    final username = account['username'] ?? 'Unknown';
    final password = account['password'] ?? '';
    final cookies = account['auth_code'] ?? '';
    final email = account['email'] ?? '';
    
    return Card(
      color: const Color(0xff1f2937),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xff374151), width: 1),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with username and delete button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person, size: 16, color: Color(0xff94a3b8)),
                          const SizedBox(width: 8),
                          Text(
                            username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.email, size: 14, color: Color(0xff94a3b8)),
                            const SizedBox(width: 8),
                            Text(
                              email,
                              style: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Delete button with better visibility
                Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () => _deleteAccount(index),
                    padding: const EdgeInsets.all(8),
                    tooltip: "Delete account",
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            const Divider(color: Color(0xff374151), height: 1),
            const SizedBox(height: 12),
            
            // Password section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Password",
                  style: TextStyle(color: Color(0xff94a3b8), fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xff0f172a),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xff1f2937)),
                        ),
                        child: SelectableText(
                          password,
                          style: const TextStyle(
                            color: Color(0xff22c55e),
                            fontFamily: 'Monospace',
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18, color: Color(0xff94a3b8)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: password));
                        _addLog("Copied", "Password copied to clipboard");
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Password copied!"),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      tooltip: "Copy password",
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Cookies section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Cookies",
                  style: TextStyle(color: Color(0xff94a3b8), fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xff0f172a),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xff1f2937)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        cookies.length > 100 ? "${cookies.substring(0, 100)}..." : cookies,
                        style: const TextStyle(
                          color: Color(0xff94a3b8),
                          fontFamily: 'Monospace',
                          fontSize: 11,
                        ),
                      ),
                      if (cookies.length > 100) ...[
                        const SizedBox(height: 4),
                        Text(
                          "${cookies.length} characters total",
                          style: const TextStyle(color: Color(0xff64748b), fontSize: 10),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Footer with timestamp if available
            if (account['timestamp'] != null) 
              Text(
                "Added: ${account['timestamp']}",
                style: const TextStyle(color: Color(0xff64748b), fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  void _deleteAccount(int index) async {
    final account = _accounts[index];
    final username = account['username'] ?? 'Unknown';
    
    // Show confirmation dialog
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to delete account '$username'?", 
                    style: const TextStyle(color: Color(0xff94a3b8))),
        backgroundColor: const Color(0xff1f2937),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Color(0xff94a3b8))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
    
    if (confirm) {
      setState(() {
        _accounts.removeAt(index);
      });
      await _saveData();
      _addLog("Deleted", "Account '$username' removed");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Deleted account '$username'"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showClearConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear All Accounts", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to delete all ${_accounts.length} accounts?", 
                    style: const TextStyle(color: Color(0xff94a3b8))),
        backgroundColor: const Color(0xff1f2937),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Color(0xff94a3b8))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _accounts.clear();
              });
              _saveData();
              _addLog("Cleared", "All accounts removed");
            },
            child: const Text("Clear All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- Fixed Settings Tab ---
  
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Webhook Settings",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Note: The webhook URL from the URL returns 404 status. Make sure to update it with a valid endpoint.",
            style: TextStyle(color: Colors.orange, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webhookController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: "Webhook URL",
              hintText: "https://your-webhook-endpoint.com",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.webhook, color: Color(0xff94a3b8)),
            ),
            onChanged: (value) {
              // Auto-save as user types
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _webhookUrl = value;
                _saveData();
              });
            },
          ),
          
          const SizedBox(height: 24),
          
          const Text(
            "Export Settings",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _filenameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: "JSON Filename",
              hintText: "accounts.json",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.description, color: Color(0xff94a3b8)),
            ),
            onChanged: (value) {
              // Auto-save as user types
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _jsonFilename = value.isNotEmpty ? value : "accounts.json";
                _saveData();
              });
            },
          ),
          
          const SizedBox(height: 24),
          
          const Text(
            "Password Settings",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xff0f172a),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff1f2937)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Current Password",
                        style: TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _currentPassword,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xff22c55e)),
                    onPressed: _generatePassword,
                    tooltip: "Generate new password",
                  ),
                  const Text("Regenerate", style: TextStyle(color: Color(0xff94a3b8), fontSize: 10)),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          
          // Save button as backup
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _webhookUrl = _webhookController.text;
                  _jsonFilename = _filenameController.text;
                });
                _saveData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("All settings saved!"),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  )
                );
              },
              icon: const Icon(Icons.save),
              label: const Text("Force Save All Settings"),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // App info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xff0f172a),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff1f2937)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "App Information",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Accounts: ${_accounts.length}",
                  style: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                ),
                Text(
                  "Logs: ${_logs.length}",
                  style: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                ),
                Text(
                  "Last save: ${DateFormat('HH:mm:ss').format(DateTime.now())}",
                  style: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}