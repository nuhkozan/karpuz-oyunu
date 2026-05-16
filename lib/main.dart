import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

const String fbUrl = 'https://karpuz-oyunu-default-rtdb.europe-west1.firebasedatabase.app';
const String _interstitialAdUnitId = 'ca-app-pub-5226177276862447/9323975802';
const String _bannerAdUnitId = 'ca-app-pub-5226177276862447/5141790853';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await MobileAds.instance.initialize();
  runApp(const KarpuzApp());
}

class KarpuzApp extends StatelessWidget {
  const KarpuzApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karpuz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: Colors.black),
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
  bool _webViewReady = false;
  InterstitialAd? _interstitialAd;
  bool _isLoadingAd = false;
  Timer? _retryTimer;
  BannerAd? _bannerAd;
  bool _bannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInterstitialAd();
    _loadBannerAd();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('FlutterAd',
          onMessageReceived: (JavaScriptMessage msg) {
        if (msg.message == 'show') _showInterstitialAd();
      })
      ..addJavaScriptChannel('FlutterFetch',
          onMessageReceived: (JavaScriptMessage msg) async {
        Map<String, dynamic> data;
        try { data = jsonDecode(msg.message) as Map<String, dynamic>; }
        catch (e) { return; }
        final id = data['id'] as String? ?? '';
        final url = data['url'] as String? ?? '';
        final method = (data['method'] as String?) ?? 'GET';
        final body = data['body'] as String?;
        try {
          http.Response response;
          final headers = {'Content-Type': 'application/json'};
          if (method == 'PUT' && body != null) {
            response = await http.put(Uri.parse(url), headers: headers, body: body)
                .timeout(const Duration(seconds: 15));
          } else {
            response = await http.get(Uri.parse(url), headers: headers)
                .timeout(const Duration(seconds: 15));
          }
          final safeBody = jsonEncode(response.body);
          _controller.runJavaScript(
              'try{window._ftCb("$id",${response.statusCode},$safeBody)}catch(e){}');
        } catch (e) {
          _controller.runJavaScript(
              'try{window._ftCb("$id",0,null)}catch(e){}');
        }
      })
      ..addJavaScriptChannel('FlutterRegister',
          onMessageReceived: (JavaScriptMessage msg) async {
        Map<String, dynamic> data;
        try { data = jsonDecode(msg.message) as Map<String, dynamic>; }
        catch (e) { return; }
        final id = data['id'] as String? ?? '';
        final name = data['name'] as String? ?? '';
        final key = name.replaceAll(RegExp(r'[.#\$\[\]/]'), '_');
        try {
          final results = await Future.wait([
            http.get(Uri.parse('$fbUrl/users/$key.json'))
                .timeout(const Duration(seconds: 10)),
            http.get(Uri.parse('$fbUrl/leaderboard/$key.json'))
                .timeout(const Duration(seconds: 10)),
          ]);
          final usersData = jsonDecode(results[0].body);
          final lbData = jsonDecode(results[1].body);
          final taken =
              (usersData != null && usersData is Map && usersData['name'] != null) ||
              (lbData != null && lbData is Map && lbData['name'] != null);
          if (!taken) {
            await http.put(
              Uri.parse('$fbUrl/users/$key.json'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'name': name, 't': DateTime.now().millisecondsSinceEpoch}),
            ).timeout(const Duration(seconds: 10));
          }
          _controller.runJavaScript(
              'try{window._regCb("$id",${taken ? 'true' : 'false'})}catch(e){}');
        } catch (e) {
          _controller.runJavaScript(
              'try{window._regCb("$id",null)}catch(e){}');
        }
      })
      ..addJavaScriptChannel('FlutterShare',
          onMessageReceived: (JavaScriptMessage msg) async {
        final text = Uri.encodeComponent(msg.message);
        final uri = Uri.parse('whatsapp://send?text=$text');
        if (await canLaunchUrl(uri)) await launchUrl(uri);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          setState(() => _webViewReady = true);
          if (_controller.platform is AndroidWebViewController) {
            (_controller.platform as AndroidWebViewController)
                .setMediaPlaybackRequiresUserGesture(false);
          }
        },
      ))
      ..loadFlutterAsset('assets/game.html');
    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() => _bannerAdLoaded = true),
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          _bannerAd = null;
          Timer(const Duration(seconds: 10), _loadBannerAd);
        },
      ),
    )..load();
  }

  void _loadInterstitialAd() {
    if (_isLoadingAd || _interstitialAd != null) return;
    _isLoadingAd = true;
    _retryTimer?.cancel();
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoadingAd = false;
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _isLoadingAd = false;
              _loadInterstitialAd();
              _controller.runJavaScript(
                'try{if(typeof window._adDone==="function")window._adDone();}catch(e){}');
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _interstitialAd = null;
              _isLoadingAd = false;
              _loadInterstitialAd();
              _controller.runJavaScript(
                'try{if(typeof window.showFallbackAd==="function")window.showFallbackAd();}catch(e){try{if(typeof window._adDone==="function")window._adDone();}catch(e2){}}');
            },
          );
        },
        onAdFailedToLoad: (err) {
          _isLoadingAd = false;
          _interstitialAd = null;
          _retryTimer = Timer(const Duration(seconds: 5), _loadInterstitialAd);
        },
      ),
    );
  }

  void _showInterstitialAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.show();
    } else {
      _loadInterstitialAd();
      _controller.runJavaScript(
        'try{if(typeof window.showFallbackAd==="function")window.showFallbackAd();}catch(e){try{if(typeof window._adDone==="function")window._adDone();}catch(e2){}}');
    }
  }

  Future<void> _saveAndGoHome() async {
    await _controller.runJavaScript('''
      try{
        if(typeof saveGameState==="function") saveGameState();
        if(typeof MUS!=="undefined"&&MUS) MUS.stop();
      }catch(e){}
    ''');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller.runJavaScript('''
        try{
          if(typeof saveGameState==="function") saveGameState();
          if(typeof MUS!=="undefined"&&MUS) MUS.stop();
          if(typeof ambientInterval!=="undefined") clearInterval(ambientInterval);
        }catch(e){}
      ''');
    } else if (state == AppLifecycleState.resumed) {
      if (_interstitialAd == null && !_isLoadingAd) _loadInterstitialAd();
      if (_bannerAd == null) _loadBannerAd();
      _controller.runJavaScript('''
        if(typeof musicOn!=="undefined" && musicOn &&
           typeof MUS!=="undefined" && MUS &&
           typeof S!=="undefined" && S.cfg && !S.dead) {
          try{MUS.start();}catch(e){}
        }
      ''');
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _interstitialAd?.dispose();
    _bannerAd?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Geri tuşu: kaydet, sonra uygulamayı minimize et
        await _saveAndGoHome();
        await SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (!_webViewReady)
                      Container(
                        color: Colors.black,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('🍉', style: TextStyle(fontSize: 64)),
                              SizedBox(height: 16),
                              CircularProgressIndicator(color: Colors.green),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_bannerAdLoaded && _bannerAd != null)
                SizedBox(
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
