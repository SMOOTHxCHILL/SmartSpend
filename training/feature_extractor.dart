import 'dart:math' as math;

/// Reimplements sklearn's TfidfVectorizer(analyzer='char_wb', ngram_range=(3,5))
/// exactly, so the exact same feature vector the Python model was trained on
/// can be computed on-device with no Python/sklearn dependency.
///
/// This algorithm was verified byte-for-byte against sklearn's actual output
/// (max abs diff = 0.0 across multiple test merchant names, including ones
/// with punctuation) before being ported here -- see export_to_onnx.py's
/// verification step in the training/ folder. Do not change the n-gram
/// logic below without re-verifying against a fresh test_vectors.json,
/// since a silent mismatch here produces confident-looking wrong
/// predictions with no error thrown anywhere.
class FeatureExtractor {
  final Map<String, int> vocabulary;
  final List<double> idf;
  final int minN;
  final int maxN;

  FeatureExtractor({
    required this.vocabulary,
    required this.idf,
    required this.minN,
    required this.maxN,
  });

  factory FeatureExtractor.fromJson(Map<String, dynamic> json) {
    final vocabRaw = json['vocabulary'] as Map<String, dynamic>;
    final vocabulary = vocabRaw.map((k, v) => MapEntry(k, v as int));

    final idfRaw = json['idf'] as List<dynamic>;
    final idf = idfRaw.map((e) => (e as num).toDouble()).toList();

    final ngramRange = json['ngram_range'] as List<dynamic>;

    return FeatureExtractor(
      vocabulary: vocabulary,
      idf: idf,
      minN: ngramRange[0] as int,
      maxN: ngramRange[1] as int,
    );
  }

  int get vocabSize => vocabulary.length;

  /// Direct port of sklearn's _char_wngrams for analyzer='char_wb'.
  /// Pads each whitespace-separated word with a single boundary space,
  /// then slides an n-length window across it for each n in [minN, maxN].
  List<String> _charWbNgrams(String text) {
    final collapsed = text
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .join(' ');

    final ngrams = <String>[];

    for (final word in collapsed.split(' ')) {
      if (word.isEmpty) continue;

      final w = ' $word ';
      final wLen = w.length;
      final upperBound = math.min(maxN + 1, wLen + 1);

      for (int n = minN; n < upperBound; n++) {
        int offset = 0;
        ngrams.add(w.substring(offset, offset + n));

        while (offset + n < wLen) {
          offset += 1;
          ngrams.add(w.substring(offset, offset + n));
        }

        if (offset == 0) break;
      }
    }

    return ngrams;
  }

  /// Computes the l2-normalized TF-IDF vector for a merchant name string.
  /// sklearn's TfidfVectorizer lowercases by default -- do the same here.
  List<double> transform(String merchantName) {
    final ngrams = _charWbNgrams(merchantName.toLowerCase());

    final counts = <int, int>{};
    for (final ng in ngrams) {
      final idx = vocabulary[ng];
      if (idx != null) {
        counts[idx] = (counts[idx] ?? 0) + 1;
      }
    }

    final vec = List<double>.filled(vocabSize, 0.0);
    for (final entry in counts.entries) {
      vec[entry.key] = entry.value * idf[entry.key];
    }

    double normSq = 0.0;
    for (final v in vec) {
      normSq += v * v;
    }

    if (normSq > 0) {
      final norm = math.sqrt(normSq);
      for (int i = 0; i < vec.length; i++) {
        vec[i] = vec[i] / norm;
      }
    }

    return vec;
  }

  /// Builds the full 305-dim feature vector matching training exactly:
  /// [text_features(300)..., amount, log_amount, hour, day_of_week, is_debit]
  List<double> buildFullFeatureVector({
    required String merchantName,
    required double amount,
    required int hour,
    required int dayOfWeek,
    required bool isDebit,
  }) {
    final textFeatures = transform(merchantName);
    final logAmount = math.log(1 + amount);

    return [
      ...textFeatures,
      amount,
      logAmount,
      hour.toDouble(),
      dayOfWeek.toDouble(),
      isDebit ? 1.0 : 0.0,
    ];
  }
}
