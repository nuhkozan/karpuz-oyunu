import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const KarpuzApp());
}

class KarpuzApp extends StatelessWidget {
  const KarpuzApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karpuz',
      debugShowCheckedModeBanner: false,
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('FlutterFetch',
          onMessageReceived: (JavaScriptMessage msg) async {
        Map<String, dynamic> data;
        try {
          data = jsonDecode(msg.message) as Map<String, dynamic>;
        } catch (e) {
          return;
        }
        final id = data['id'] as String? ?? '';
        final url = data['url'] as String? ?? '';
        final method = (data['method'] as String?) ?? 'GET';
        final body = data['body'] as String?;
        try {
          http.Response response;
          final headers = {'Content-Type': 'application/json'};
          if (method == 'PUT' && body != null) {
            response = await http.put(
              Uri.parse(url), headers: headers, body: body,
            ).timeout(const Duration(seconds: 15));
          } else {
            response = await http.get(
              Uri.parse(url), headers: headers,
            ).timeout(const Duration(seconds: 15));
          }
          final safeBody = jsonEncode(response.body);
          _controller.runJavaScript(
            'try{window._ftCb("$id",${response.statusCode},$safeBody)}catch(e){}'
          );
        } catch (e) {
          _controller.runJavaScript(
            'try{window._ftCb("$id",0,null)}catch(e){}'
          );
        }
      })
      ..addJavaScriptChannel('FlutterShare',
          onMessageReceived: (JavaScriptMessage msg) async {
        final text = Uri.encodeComponent(msg.message);
        final uri = Uri.parse('whatsapp://send?text=$text');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          // Firebase bağlantısını test et
          _controller.runJavaScript(
            'console.log("FlutterFetch available:", typeof FlutterFetch)'
          );
        },
      ))
      ..loadFlutterAsset('assets/game.html');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller.runJavaScript(
        'if(typeof saveGameState==="function")saveGameState();'
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
