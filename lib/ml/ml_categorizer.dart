import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'feature_extractor.dart';

/// On-device category classifier. Falls back gracefully (returns null) on
/// any failure so a broken/missing model never crashes the resolver flow --
/// callers should treat a null result the same as "no ML guess available"
/// and fall back to the existing MCC lookup / 'Other' default.
class MlCategorizer {
  static final MlCategorizer _instance = MlCategorizer._internal();

  factory MlCategorizer() => _instance;

  MlCategorizer._internal();

  static const _modelAsset = 'assets/ml/categorizer.onnx';
  static const _vectorizerAsset = 'assets/ml/vectorizer.json';
  static const _labelsAsset = 'assets/ml/label_encoder.json';

  OnnxRuntime? _runtime;
  OrtSession? _session;
  FeatureExtractor? _extractor;
  List<String>? _labels;

  bool get isReady => _session != null && _extractor != null && _labels != null;

  /// Idempotent -- safe to call from multiple places (app startup,
  /// individual MerchantResolver instances) without reloading the ONNX
  /// session repeatedly, since it's the same singleton either way.
  Future<void> load() async {
    if (isReady) return;

    try {
      final vectorizerJson = jsonDecode(
        await rootBundle.loadString(_vectorizerAsset),
      ) as Map<String, dynamic>;
      _extractor = FeatureExtractor.fromJson(vectorizerJson);

      final labelsJson = jsonDecode(
        await rootBundle.loadString(_labelsAsset),
      ) as Map<String, dynamic>;
      _labels = (labelsJson['classes'] as List<dynamic>).cast<String>();

      _runtime = OnnxRuntime();
      _session = await _runtime!.createSessionFromAsset(_modelAsset);
    } catch (e) {
      // Model failed to load -- isReady stays false, predict() will
      // short-circuit to null. Not fatal to the app.
      _session = null;
    }
  }

  /// Returns a predicted category for a brand-new merchant, or null if the
  /// model isn't loaded / inference fails. This is a same-session GUESS,
  /// not a verified label -- callers must NOT treat this as category_source
  /// = 'user_corrected'. It's meant to replace a blind 'Other' default with
  /// a smarter one, still fully overridable via the correction UI.
  Future<String?> predict({
    required String merchantName,
    required double amount,
    required DateTime transactionDate,
    required bool isDebit,
  }) async {
    if (!isReady) return null;

    try {
      final features = _extractor!.buildFullFeatureVector(
        merchantName: merchantName,
        amount: amount,
        hour: transactionDate.hour,
        dayOfWeek: transactionDate.weekday - 1, // Dart: Mon=1..Sun=7, Python: Mon=0..Sun=6
        isDebit: isDebit,
      );

      // NOTE: verify this call signature against your installed
      // flutter_onnxruntime version -- OrtValue.fromList(data, shape) is
      // current as of the version checked while building this, but plugin
      // APIs do shift between releases. If this doesn't compile, check
      // the package's own example for the exact current signature.
      final inputTensor = await OrtValue.fromList(features, [1, features.length]);

      final outputs = await _session!.run({'input': inputTensor});
      inputTensor.dispose();

      final labelOutput = outputs['label'];
      if (labelOutput == null) return null;

      final labelData = await labelOutput.asList();
      for (final tensor in outputs.values) {
        tensor.dispose();
      }

      if (labelData.isEmpty) return null;

      final classIndex = (labelData[0] as num).toInt();
      if (classIndex < 0 || classIndex >= _labels!.length) return null;

      return _labels![classIndex];
    } catch (e) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
  }
}
