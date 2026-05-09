import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
      ..addJavaScriptChannel('FlutterFetch', onMessageReceived: (msg) async {
        try {
          final data = jsonDecode(msg.message);
          final id = data['id'] as String;
          final url = data['url'] as String;
          final method = (data['method'] as String?) ?? 'GET';
          final body = data['body'] as String?;
          http.Response response;
          if (method == 'PUT' && body != null) {
            response = await http.put(Uri.parse(url),
              headers: {'Content-Type': 'application/json'}, body: body)
              .timeout(const Duration(seconds: 10));
          } else {
            response = await http.get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));
          }
          final escaped = response.body
            .replaceAll('\\', '\\\\')
            .replaceAll('"', '\\"')
            .replaceAll('\n', '\\n')
            .replaceAll('\r', '');
          await _controller.runJavaScript(
            'window._ftCb("$id", ${response.statusCode}, "$escaped")'
          );
        } catch (e) {
          try {
            final data = jsonDecode(msg.message);
            await _controller.runJavaScript(
              'window._ftCb("${data['id']}", 0, null)'
            );
          } catch (_) {}
        }
      })
      ..addJavaScriptChannel('FlutterShare', onMessageReceived: (msg) async {
        final text = Uri.encodeComponent(msg.message);
        final url = 'whatsapp://send?text=$text';
        await _controller.runJavaScript(
          'window.location.href = "$url"'
        );
      })
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
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        await _controller.runJavaScript(
          'if(typeof saveGameState==="function")saveGameState();'
        );
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
