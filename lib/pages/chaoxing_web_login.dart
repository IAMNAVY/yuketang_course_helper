import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as web;

import '../session/cookie.dart';

class ChaoxingWebLoginPage extends StatefulWidget {
  const ChaoxingWebLoginPage({super.key, required this.onAuthenticated});

  final Future<bool> Function(BuildContext context) onAuthenticated;

  @override
  State<ChaoxingWebLoginPage> createState() => _ChaoxingWebLoginPageState();
}

class _ChaoxingWebLoginPageState extends State<ChaoxingWebLoginPage> {
  static final _loginUrl = web.WebUri(
    'https://passport2.chaoxing.com/login?refer=https%3A%2F%2Fi.chaoxing.com',
  );

  web.InAppWebViewController? _controller;
  bool _ready = false;
  bool _checking = false;
  double _progress = 0;
  String? _pageError;
  String? _message;
  String? _attemptedSession;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      // Each added account starts in a fresh WebView login session. Existing
      // accounts retain their independent API CookieJars.
      await web.CookieManager.instance().deleteAllCookies();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => _pageError = '无法启动网页登录，请返回后重试。');
      }
    }
  }

  Future<void> _readSession({bool manual = false}) async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    var imported = false;
    try {
      final manager = web.CookieManager.instance();
      final entries = <({Uri origin, io.Cookie cookie})>[];
      final sharedCookies = <String>{};
      for (final origin in CookieManager.chaoxingOrigins) {
        final cookies = await manager.getCookies(
          url: web.WebUri(origin.toString()),
        );
        for (final cookie in cookies) {
          final key = '${cookie.name}=${cookie.value}';
          if (origin.host == 'chaoxing.com') {
            sharedCookies.add(key);
          } else if (cookie.domain == null && sharedCookies.contains(key)) {
            // Android only returns names and values. Do not duplicate a shared
            // domain cookie as a second host cookie on every API hostname.
            continue;
          }
          try {
            final value = io.Cookie(cookie.name, cookie.value)
              ..domain =
                  cookie.domain ??
                  (origin.host == 'chaoxing.com'
                      ? '.chaoxing.com'
                      : origin.host)
              ..path = cookie.path ?? '/'
              ..secure = cookie.isSecure ?? true
              ..httpOnly = cookie.isHttpOnly ?? false;
            if (cookie.expiresDate != null) {
              value.expires = DateTime.fromMillisecondsSinceEpoch(
                cookie.expiresDate!.toInt(),
                isUtc: true,
              );
            }
            entries.add((origin: origin, cookie: value));
          } catch (_) {
            // Some site cookies contain values Dart cannot represent. Keep
            // importing the remaining session cookies without logging values.
            continue;
          }
        }
      }

      final auth =
          entries
              .where(
                (entry) =>
                    {'_uid', 'UID', '_d', 'vc3'}.contains(entry.cookie.name),
              )
              .map((entry) => '${entry.cookie.name}=${entry.cookie.value}')
              .toSet()
              .toList()
            ..sort();
      final hasUser = entries.any(
        (entry) =>
            {'_uid', 'UID'}.contains(entry.cookie.name) &&
            (int.tryParse(entry.cookie.value) ?? 0) > 0,
      );
      if (!hasUser) {
        if (manual && mounted) {
          setState(() => _message = '尚未检测到登录，请先在网页中完成登录和验证。');
        }
        return;
      }
      final fingerprint = auth.join(';');
      if (!manual && fingerprint == _attemptedSession) return;
      _attemptedSession = fingerprint;

      await CookieManager.tempCookieJar.deleteAll();
      for (final entry in entries) {
        await CookieManager.tempCookieJar.saveFromResponse(entry.origin, [
          entry.cookie,
        ]);
      }
      imported = true;
      if (!mounted) return;
      final success = await widget.onAuthenticated(context);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop();
      } else {
        setState(() => _message = '未能验证网页会话。请确认登录完成，再点“完成登录”。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '读取登录状态失败，请检查网络后重试。');
      }
    } finally {
      if (imported) await CookieManager.tempCookieJar.deleteAll();
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _retry() async {
    setState(() {
      _pageError = null;
      _message = null;
      _attemptedSession = null;
    });
    if (!_ready) {
      await _prepare();
    } else {
      await _controller?.loadUrl(urlRequest: web.URLRequest(url: _loginUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习通网页登录'),
        actions: [
          IconButton(
            onPressed: _checking ? null : _retry,
            tooltip: '重新打开登录页',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_progress < 1 && _pageError == null)
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            Expanded(
              child: _pageError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_pageError!, textAlign: TextAlign.center),
                          FilledButton(
                            onPressed: _retry,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : web.InAppWebView(
                      initialUrlRequest: web.URLRequest(url: _loginUrl),
                      initialSettings: web.InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        thirdPartyCookiesEnabled: true,
                        sharedCookiesEnabled: true,
                        useShouldOverrideUrlLoading: true,
                      ),
                      onWebViewCreated: (controller) =>
                          _controller = controller,
                      onProgressChanged: (_, progress) {
                        if (mounted) setState(() => _progress = progress / 100);
                      },
                      onLoadStop: (_, _) => _readSession(),
                      onReceivedError: (_, request, _) {
                        if (request.isForMainFrame == true && mounted) {
                          setState(() => _pageError = '网页登录页面加载失败，请检查网络后重试。');
                        }
                      },
                      shouldOverrideUrlLoading: (_, action) async {
                        final scheme = action.request.url?.scheme;
                        return scheme == 'https' || scheme == 'http'
                            ? web.NavigationActionPolicy.ALLOW
                            : web.NavigationActionPolicy.CANCEL;
                      },
                    ),
            ),
            if (_message != null)
              Semantics(
                liveRegion: true,
                child: Text(_message!, textAlign: TextAlign.center),
              ),
            const Text('在官方网页完成登录，成功后会自动返回。', textAlign: TextAlign.center),
            FilledButton.icon(
              onPressed: !_ready || _checking
                  ? null
                  : () => _readSession(manual: true),
              icon: Icon(_checking ? Icons.hourglass_top : Icons.check),
              label: Text(_checking ? '正在验证登录' : '完成登录'),
            ),
          ],
        ),
      ),
    );
  }
}
