import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart' as custom_tabs;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// Closes any currently-open in-app browser (SFSafariViewController / Chrome
/// Custom Tab). Safe to call on desktop — it's a no-op there.
Future<void> closeInAppBrowser() async {
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    await custom_tabs.closeCustomTabs();
  }
}

/// Launches [uri] using an in-app browser on iOS/Android (SFSafariViewController
/// / Chrome Custom Tabs) and falls back to [url_launcher] on desktop platforms.
///
/// This satisfies App Store requirements that OAuth flows must not leave the
/// app to the default system browser.
Future<void> launchInAppBrowser(Uri uri, {BuildContext? context}) async {
  // On iOS and Android, use flutter_custom_tabs (SFSafariViewController /
  // Chrome Custom Tabs). These keep the user inside the app while providing
  // a secure, system-managed browser view that supports deep-link redirects.
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    await custom_tabs.launchUrl(
      uri,
      customTabsOptions: custom_tabs.CustomTabsOptions(
        shareState: custom_tabs.CustomTabsShareState.off,
        urlBarHidingEnabled: true,
        showTitle: true,
      ),
      safariVCOptions: custom_tabs.SafariViewControllerOptions(
        barCollapsingEnabled: true,
      ),
    );
  } else {
    // macOS, Windows, Linux, web — open in external browser.
    if (await url_launcher.canLaunchUrl(uri)) {
      await url_launcher.launchUrl(
        uri,
        mode: url_launcher.LaunchMode.externalApplication,
      );
    } else {
      throw Exception('Could not launch browser');
    }
  }
}

/// Launches an OAuth authentication session using [FlutterWebAuth2].
///
/// On macOS 10.15+ and iOS 12+ this uses `ASWebAuthenticationSession`,
/// satisfying App Store requirements (Guideline 4.0) that sign-in must not
/// leave the app for the default system browser.
///
/// On Android it uses Chrome Auth Tab; on Windows/Linux a webview approach.
///
/// This is a **blocking async call** — it opens the auth session, waits for
/// the redirect to [callbackUrlScheme], and returns the callback [Uri].
Future<Uri> launchAuthSession(
  Uri uri, {
  required String callbackUrlScheme,
}) async {
  final result = await FlutterWebAuth2.authenticate(
    url: uri.toString(),
    callbackUrlScheme: callbackUrlScheme,
    options: const FlutterWebAuth2Options(),
  );
  await closeInAppBrowser();
  return Uri.parse(result);
}
