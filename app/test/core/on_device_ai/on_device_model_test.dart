import 'package:democracy/src/core/on_device_ai/on_device_cache.dart';
import 'package:democracy/src/core/on_device_ai/on_device_model.dart';
import 'package:democracy/src/core/on_device_ai/platform_on_device_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('availability', () {
    test('an available model names itself', () {
      final state = ModelAvailability.fromMap({
        'status': 'available',
        'model': 'apple-foundation-models/ios-26.4',
      });
      expect(state, isA<ModelAvailable>());
      expect(
        (state as ModelAvailable).modelVersion,
        'apple-foundation-models/ios-26.4',
      );
    });

    test('each reason the bridge sends is read, with its words', () {
      final cases = {
        'deviceNotEligible': '지원 기기 아님',
        'appleIntelligenceNotEnabled': 'Apple Intelligence 꺼짐',
        'modelNotReady': '모델 준비 중',
        'modelDownloadable': '모델 준비 중',
        'unsupportedLanguage': '한국어 미지원',
        'osTooOld': 'OS 버전 미지원',
      };
      for (final MapEntry(key: raw, value: label) in cases.entries) {
        final state = ModelAvailability.fromMap({
          'status': 'unavailable',
          'reason': raw,
        });
        expect(state, isA<ModelUnavailable>(), reason: raw);
        final reason = (state as ModelUnavailable).reason;
        expect(reason.name, raw);
        expect(reason.label, label);
      }
    });

    test('an answer that is not understood is not taken as available', () {
      for (final raw in [
        null,
        'yes',
        {'status': 'available'},
        {'status': 'available', 'model': ''},
        {'status': 'unavailable', 'reason': 'somethingNew'},
      ]) {
        final state = ModelAvailability.fromMap(raw);
        expect(state, isA<ModelUnavailable>(), reason: '$raw');
        expect(
          (state as ModelUnavailable).reason,
          ModelUnavailableReason.deviceNotEligible,
        );
      }
    });

    test('a device with no model refuses every run with its reason', () async {
      const model = UnavailableOnDeviceModel(
        ModelUnavailableReason.appleIntelligenceNotEnabled,
      );
      const request = OnDeviceRequest(
        task: OnDeviceTask.match,
        instructions: '',
        prompt: '',
      );
      await expectLater(
        model.generate(request),
        throwsA(
          isA<OnDeviceUnavailableException>().having(
            (e) => e.reason,
            'reason',
            ModelUnavailableReason.appleIntelligenceNotEnabled,
          ),
        ),
      );
      await expectLater(
        model.stream(request).drain<void>(),
        throwsA(isA<OnDeviceUnavailableException>()),
      );
    });
  });

  group('the platform bridge', () {
    const channel = MethodChannel('test/on_device_ai');
    const model = PlatformOnDeviceModel(channel: channel);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const request = OnDeviceRequest(
      task: OnDeviceTask.stances,
      instructions: 'i',
      prompt: 'p',
    );

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('reads availability and passes the task through', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'availability' => {'status': 'available', 'model': 'gemini-nano/x'},
          'generate' => '{"items":[]}',
          _ => null,
        };
      });

      final state = await model.availability();
      expect((state as ModelAvailable).modelVersion, 'gemini-nano/x');
      expect(await model.generate(request), '{"items":[]}');
      expect(calls.last.arguments, {
        'task': 'stances',
        'instructions': 'i',
        'prompt': 'p',
        'format': '',
      });
    });

    test('no bridge at all is an unsupported platform, not a crash', () async {
      // No handler: MissingPluginException.
      final state = await model.availability();
      expect(
        (state as ModelUnavailable).reason,
        ModelUnavailableReason.unsupportedPlatform,
      );
      await expectLater(
        model.generate(request),
        throwsA(isA<OnDeviceUnavailableException>()),
      );
    });

    test('native errors keep their meaning', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'unavailable',
          message: 'appleIntelligenceNotEnabled',
        );
      });
      await expectLater(
        model.generate(request),
        throwsA(
          isA<OnDeviceUnavailableException>().having(
            (e) => e.reason,
            'reason',
            ModelUnavailableReason.appleIntelligenceNotEnabled,
          ),
        ),
      );

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'guardrail');
      });
      await expectLater(
        model.generate(request),
        throwsA(
          isA<OnDeviceModelException>().having(
            (e) => e.code,
            'code',
            'guardrail',
          ),
        ),
      );

      messenger.setMockMethodCallHandler(channel, (call) async => '  ');
      await expectLater(
        model.generate(request),
        throwsA(
          isA<OnDeviceModelException>().having((e) => e.code, 'code', 'output'),
        ),
      );
    });
  });

  group('reading the model output', () {
    test('takes the object out of a fence or a sentence', () {
      expect(decodeModelJson('{"a":1}'), {'a': 1});
      expect(decodeModelJson('```json\n{"a":1}\n```'), {'a': 1});
      expect(decodeModelJson('결과입니다: {"a":{"b":2}} 끝'), {
        'a': {'b': 2},
      });
    });

    test('refuses what is not an object', () {
      for (final text in ['', '[1,2]', '{"a":', 'no json', '{a:1}']) {
        expect(
          () => decodeModelJson(text),
          throwsA(isA<OnDeviceModelException>()),
          reason: text,
        );
        expect(tryDecodeModelJson(text), isNull, reason: text);
      }
    });
  });

  group('the cache key', () {
    String key({
      OnDeviceTask task = OnDeviceTask.match,
      String district = 'nec-1',
      Object? input = const {
        'interests': ['세금'],
      },
      String model = 'm1',
    }) => onDeviceCacheKey(
      task: task,
      districtId: district,
      input: input,
      modelVersion: model,
    );

    test('is the same for the same run', () {
      expect(key(), key());
    });

    test('changes with the task, district, input and model version', () {
      final base = key();
      expect(key(task: OnDeviceTask.stances), isNot(base));
      expect(key(district: 'nec-2'), isNot(base));
      expect(
        key(
          input: const {
            'interests': ['세금', '복지'],
          },
        ),
        isNot(base),
      );
      expect(key(model: 'm2'), isNot(base));
    });

    test('does not carry the input itself', () {
      expect(key(), isNot(contains('세금')));
    });

    test('the in-memory cache gives back what was written', () async {
      final cache = InMemoryOnDeviceResultCache();
      expect(await cache.read('k'), isNull);
      await cache.write('k', {'a': 1});
      expect(await cache.read('k'), {'a': 1});
    });
  });
}
