import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_review/in_app_review.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

const String fbUrl = 'https://karpuz-oyunu-default-rtdb.europe-west1.firebasedatabase.app';
const String _interstitialAdUnitId = 'ca-app-pub-5226177276862447/9323975802';
const String _bannerAdUnitId      = 'ca-app-pub-5226177276862447/5141790853';
const String _rewardedAdUnitId    = 'ca-app-pub-5226177276862447/7990249812';

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
  Timer? _loadTimeoutTimer;
  Timer? _periodicAdTimer;
  bool _isGameScreenActive = false; // Hata 5: sadece oyundayken reklam

  // Interstitial
  InterstitialAd? _interstitialAd;
  bool _isLoadingAd = false;
  Timer? _retryTimer;

  // Banner
  BannerAd? _bannerAd;
  bool _bannerAdLoaded = false;
  bool _bannerVisible = false;

  // Rewarded
  RewardedAd? _rewardedAd;
  bool _isLoadingRewarded = false;

  // In-App Review
  final InAppReview _inAppReview = InAppReview.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInterstitialAd();
    _loadBannerAd();
    _loadRewardedAd();

    // Her 30 dakikada bir otomatik interstitial â€” sadece oyun ekranÄ±ndayken (Hata 5)
    _periodicAdTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_isGameScreenActive) _showInterstitialAd();
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)

      // -- Banner goster/gizle --
      ..addJavaScriptChannel('FlutterBanner',
          onMessageReceived: (JavaScriptMessage msg) {
        final show = msg.message == 'show';
        if (_bannerVisible != show) {
          setState(() { _bannerVisible = show; });
        }
      })

      // -- Oyun ekranÄ± durumu (Hata 5) --
      ..addJavaScriptChannel('FlutterGameState',
          onMessageReceived: (JavaScriptMessage msg) {
        _isGameScreenActive = msg.message == 'game';
      })

      // -- Interstitial --
      ..addJavaScriptChannel('FlutterAd',
          onMessageReceived: (JavaScriptMessage msg) {
        if (msg.message == 'show') _showInterstitialAd();
      })

      // -- Rewarded --
      ..addJavaScriptChannel('FlutterRewardedAd',
          onMessageReceived: (JavaScriptMessage msg) {
        if (msg.message == 'show') _showRewardedAd();
      })

      // -- In-App Review (Level 8 - Hata 1) --
      ..addJavaScriptChannel('FlutterReview',
          onMessageReceived: (JavaScriptMessage msg) async {
        if (msg.message == 'show') {
          try {
            // isAvailable() kontrolÃ¼ olmadan direkt dene â€” Google kendi filtresini yapar
            await _inAppReview.requestReview();
          } catch (e) {}
        }
      })

      // -- Firebase Fetch --
      ..addJavaScriptChannel('FlutterFetch',
          onMessageReceived: (JavaScriptMessage msg) async {
        Map<String, dynamic> data;
        try { data = jsonDecode(msg.message) as Map<String, dynamic>; }
        catch (e) { return; }
        final id     = data['id']     as String? ?? '';
        final url    = data['url']    as String? ?? '';
        final method = (data['method'] as String?) ?? 'GET';
        final body   = data['body']   as String?;
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

      // -- Register --
      ..addJavaScriptChannel('FlutterRegister',
          onMessageReceived: (JavaScriptMessage msg) async {
        Map<String, dynamic> data;
        try { data = jsonDecode(msg.message) as Map<String, dynamic>; }
        catch (e) { return; }
        final id   = data['id']   as String? ?? '';
        final name = data['name'] as String? ?? '';
        final key  = name.replaceAll(RegExp(r'[.#\$\[\]/]'), '_');
        try {
          final results = await Future.wait([
            http.get(Uri.parse('$fbUrl/users/$key.json'))
                .timeout(const Duration(seconds: 10)),
            http.get(Uri.parse('$fbUrl/leaderboard/$key.json'))
                .timeout(const Duration(seconds: 10)),
          ]);
          final usersData = jsonDecode(results[0].body);
          final lbData    = jsonDecode(results[1].body);
          final taken =
              (usersData != null && usersData is Map && usersData['name'] != null) ||
              (lbData    != null && lbData    is Map && lbData['name']    != null);
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

      // -- WhatsApp Share --
      ..addJavaScriptChannel('FlutterShare',
          onMessageReceived: (JavaScriptMessage msg) async {
        final text = Uri.encodeComponent(msg.message);
        final uri  = Uri.parse('whatsapp://send?text=$text');
        if (await canLaunchUrl(uri)) await launchUrl(uri);
      })

      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          _loadTimeoutTimer?.cancel();
          setState(() => _webViewReady = true);
          if (_controller.platform is AndroidWebViewController) {
            final androidController = _controller.platform as AndroidWebViewController;
            androidController.setMediaPlaybackRequiresUserGesture(false);
          }
        },
      ))
      ..loadFlutterAsset('assets/game.html');

    _loadTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!_webViewReady) {
        _controller.loadFlutterAsset('assets/game.html');
      }
    });

    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
  }

  // --- Banner ---
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

  // --- Interstitial ---
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

  // --- Rewarded ---
  void _loadRewardedAd() {
    if (_isLoadingRewarded || _rewardedAd != null) return;
    _isLoadingRewarded = true;
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoadingRewarded = false;
          _rewardedAd = ad;
        },
        onAdFailedToLoad: (err) {
          _isLoadingRewarded = false;
          _rewardedAd = null;
          Timer(const Duration(seconds: 10), _loadRewardedAd);
        },
      ),
    );
  }

  void _showRewardedAd() {
    if (_rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _rewardedAd = null;
          _loadRewardedAd();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          _rewardedAd = null;
          _loadRewardedAd();
          _controller.runJavaScript(
            'try{if(typeof window._rewardedDone==="function")window._rewardedDone();}catch(e){}');
        },
      );
      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          _controller.runJavaScript(
            'try{if(typeof window._rewardedDone==="function")window._rewardedDone();}catch(e){}');
        },
      );
    } else {
      _loadRewardedAd();
      _controller.runJavaScript(
        'try{if(typeof window.showFallbackAd==="function")window.showFallbackAd(true);}catch(e){try{if(typeof window._rewardedDone==="function")window._rewardedDone();}catch(e2){}}');
    }
  }

  // --- Lifecycle ---
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
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _controller.runJavaScript('''
        try{
          if(typeof saveGameState==="function") saveGameState();
          if(typeof MUS!=="undefined"&&MUS){ MUS.stop(); MUS.muted=true; }
          if(typeof ambientInterval!=="undefined") clearInterval(ambientInterval);
          if(typeof AC!=="undefined"&&AC&&AC.state!=="closed") AC.suspend();
        }catch(e){}
      ''');
    } else if (state == AppLifecycleState.resumed) {
      if (_interstitialAd == null && !_isLoadingAd) _loadInterstitialAd();
      if (_bannerAd == null) _loadBannerAd();
      if (_rewardedAd == null && !_isLoadingRewarded) _loadRewardedAd();
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
    _loadTimeoutTimer?.cancel();
    _periodicAdTimer?.cancel();
    _interstitialAd?.dispose();
    _bannerAd?.dispose();
    _rewardedAd?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
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
                    WebViewWidget(
                      controller: _controller,
                      gestureRecognizers: {
                        Factory<OneSequenceGestureRecognizer>(
                          () => EagerGestureRecognizer(),
                        ),
                      },
                    ),
                    if (!_webViewReady)
                      Container(
                        color: Colors.black,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('ğŸ‰', style: TextStyle(fontSize: 64)),
                              SizedBox(height: 16),
                              CircularProgressIndicator(color: Colors.green),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_bannerAdLoaded && _bannerAd != null && _bannerVisible)
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
