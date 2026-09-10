// Standalone verification -- no Flutter dependency, run directly:
//   dart run verify_features.dart
//
// Compares FeatureExtractor's output against test_vectors.json (generated
// by export_to_onnx.py from the real Python pipeline) to confirm the Dart
// port produces numerically identical features before it's ever wired into
// the app. If this doesn't pass, nothing downstream can be trusted.

import 'dart:convert';
import 'dart:io';
import 'feature_extractor.dart';

void main() async {
  final vectorizerJson = jsonDecode(
    await File('model/vectorizer.json').readAsString(),
  ) as Map<String, dynamic>;

  final testVectors = jsonDecode(
    await File('model/test_vectors.json').readAsString(),
  ) as List<dynamic>;

  final extractor = FeatureExtractor.fromJson(vectorizerJson);

  int passed = 0;
  int failed = 0;

  for (final testCase in testVectors) {
    final input = testCase['input'] as Map<String, dynamic>;
    final expected = (testCase['feature_vector'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();

    final actual = extractor.buildFullFeatureVector(
      merchantName: input['merchant_name'] as String,
      amount: (input['amount'] as num).toDouble(),
      hour: input['hour'] as int,
      dayOfWeek: input['day_of_week'] as int,
      isDebit: (input['is_debit'] as int) == 1,
    );

    if (actual.length != expected.length) {
      print('FAIL (${input['merchant_name']}): length mismatch '
          '${actual.length} vs ${expected.length}');
      failed++;
      continue;
    }

    double maxDiff = 0.0;
    for (int i = 0; i < actual.length; i++) {
      final diff = (actual[i] - expected[i]).abs();
      if (diff > maxDiff) maxDiff = diff;
    }

    if (maxDiff < 1e-6) {
      print('PASS (${input['merchant_name']}): max diff = $maxDiff');
      passed++;
    } else {
      print('FAIL (${input['merchant_name']}): max diff = $maxDiff '
          '(expected < 1e-6)');
      failed++;
    }
  }

  print('\n$passed passed, $failed failed');

  if (failed > 0) {
    print('\nDo NOT wire this into the app until every case passes.');
    exit(1);
  } else {
    print('\nAll feature vectors match Python exactly. Safe to proceed.');
  }
}
