import 'dart:convert';
import 'dart:io';

import 'package:course_helper/session/cookie.dart';
import 'package:course_helper/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageManager.initialize();
    await CookieManager.tempCookieJar.deleteAll();
  });

  test(
    'web login keeps shared and host-only cookies in their proper scope',
    () async {
      final shared = Cookie('_uid', 'test-user')
        ..domain = '.chaoxing.com'
        ..path = '/'
        ..secure = true
        ..httpOnly = true
        ..expires = DateTime.now().add(const Duration(days: 1));
      final hostOnly = Cookie('login_session', 'test-session')..path = '/';
      await CookieManager.tempCookieJar.saveFromResponse(
        Uri.parse('https://passport2.chaoxing.com/'),
        [shared, hostOnly],
      );
      await CookieManager.saveTempCookies('web-test');
      final jar = CookieManager.getCookieJarForUser('web-test')!;
      final courses = await jar.loadForRequest(
        Uri.parse('https://mooc1-api.chaoxing.com/'),
      );
      expect(courses.map((cookie) => cookie.name), contains('_uid'));
      expect(
        courses.map((cookie) => cookie.name),
        isNot(contains('login_session')),
      );
      final login = await jar.loadForRequest(
        Uri.parse('https://passport2.chaoxing.com/'),
      );
      expect(login.map((cookie) => cookie.name), contains('login_session'));
      expect(
        await jar.loadForRequest(Uri.parse('https://example.com/')),
        isEmpty,
      );

      final stored =
          jsonDecode(StorageManager.prefs.getString('cookies_web-test')!)
              as List;
      expect(
        stored.any(
          (entry) =>
              entry['origin'] == 'https://passport2.chaoxing.com/' &&
              entry['name'] == 'login_session',
        ),
        isTrue,
      );
      expect(
        stored
            .where((entry) => entry['name'] == '_uid')
            .every(
              (entry) => entry['httpOnly'] == true && entry['expires'] is int,
            ),
        isTrue,
      );
      expect(
        await CookieManager.tempCookieJar.loadForRequest(
          Uri.parse('https://chaoxing.com/'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'importing another account cannot replace the first account cookies',
    () async {
      for (final user in ['first', 'second']) {
        await CookieManager.tempCookieJar.saveFromResponse(
          Uri.parse('https://chaoxing.com/'),
          [
            Cookie('_uid', user)
              ..domain = '.chaoxing.com'
              ..path = '/',
          ],
        );
        await CookieManager.saveTempCookies(user);
      }
      for (final user in ['first', 'second']) {
        final cookies = await CookieManager.getCookieJarForUser(
          user,
        )!.loadForRequest(Uri.parse('https://mobilelearn.chaoxing.com/'));
        expect(
          cookies.singleWhere((cookie) => cookie.name == '_uid').value,
          user,
        );
      }
    },
  );
}
