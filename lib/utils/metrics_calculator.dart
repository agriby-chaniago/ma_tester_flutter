import 'dart:typed_data';

/// Utility class untuk menghitung evaluation metrics
/// antara predicted mask dan ground truth mask
class MetricsCalculator {
  /// Calculate Dice Coefficient (F1 Score untuk binary segmentation)
  ///
  /// Dice = 2 * |X ∩ Y| / (|X| + |Y|)
  /// Range: [0, 1], higher is better
  static double dice(Uint8List predicted, Uint8List groundTruth) {
    if (predicted.length != groundTruth.length) {
      throw ArgumentError('Masks must have the same size');
    }

    int intersection = 0;
    int predSum = 0;
    int gtSum = 0;

    for (int i = 0; i < predicted.length; i++) {
      final pred = predicted[i] > 0 ? 1 : 0;
      final gt = groundTruth[i] > 0 ? 1 : 0;

      intersection += pred & gt;
      predSum += pred;
      gtSum += gt;
    }

    if (predSum + gtSum == 0) {
      return 1.0; // Both masks are empty, perfect match
    }

    return (2.0 * intersection) / (predSum + gtSum);
  }

  /// Calculate Intersection over Union (IoU / Jaccard Index)
  ///
  /// IoU = |X ∩ Y| / |X ∪ Y|
  /// Range: [0, 1], higher is better
  static double iou(Uint8List predicted, Uint8List groundTruth) {
    if (predicted.length != groundTruth.length) {
      throw ArgumentError('Masks must have the same size');
    }

    int intersection = 0;
    int union = 0;

    for (int i = 0; i < predicted.length; i++) {
      final pred = predicted[i] > 0 ? 1 : 0;
      final gt = groundTruth[i] > 0 ? 1 : 0;

      intersection += pred & gt;
      union += pred | gt;
    }

    if (union == 0) {
      return 1.0; // Both masks are empty
    }

    return intersection / union;
  }

  /// Calculate Precision (Positive Predictive Value)
  ///
  /// Precision = TP / (TP + FP)
  /// Range: [0, 1], higher is better
  static double precision(Uint8List predicted, Uint8List groundTruth) {
    if (predicted.length != groundTruth.length) {
      throw ArgumentError('Masks must have the same size');
    }

    int truePositive = 0;
    int falsePositive = 0;

    for (int i = 0; i < predicted.length; i++) {
      final pred = predicted[i] > 0 ? 1 : 0;
      final gt = groundTruth[i] > 0 ? 1 : 0;

      if (pred == 1 && gt == 1) {
        truePositive++;
      } else if (pred == 1 && gt == 0) {
        falsePositive++;
      }
    }

    final total = truePositive + falsePositive;
    if (total == 0) {
      return 0.0; // No positive predictions
    }

    return truePositive / total;
  }

  /// Calculate Recall (Sensitivity / True Positive Rate)
  ///
  /// Recall = TP / (TP + FN)
  /// Range: [0, 1], higher is better
  static double recall(Uint8List predicted, Uint8List groundTruth) {
    if (predicted.length != groundTruth.length) {
      throw ArgumentError('Masks must have the same size');
    }

    int truePositive = 0;
    int falseNegative = 0;

    for (int i = 0; i < predicted.length; i++) {
      final pred = predicted[i] > 0 ? 1 : 0;
      final gt = groundTruth[i] > 0 ? 1 : 0;

      if (pred == 1 && gt == 1) {
        truePositive++;
      } else if (pred == 0 && gt == 1) {
        falseNegative++;
      }
    }

    final total = truePositive + falseNegative;
    if (total == 0) {
      return 0.0; // No ground truth positives
    }

    return truePositive / total;
  }

  /// Calculate Specificity (True Negative Rate)
  ///
  /// Specificity = TN / (TN + FP)
  /// Range: [0, 1], higher is better
  static double specificity(Uint8List predicted, Uint8List groundTruth) {
    if (predicted.length != groundTruth.length) {
      throw ArgumentError('Masks must have the same size');
    }

    int trueNegative = 0;
    int falsePositive = 0;

    for (int i = 0; i < predicted.length; i++) {
      final pred = predicted[i] > 0 ? 1 : 0;
      final gt = groundTruth[i] > 0 ? 1 : 0;

      if (pred == 0 && gt == 0) {
        trueNegative++;
      } else if (pred == 1 && gt == 0) {
        falsePositive++;
      }
    }

    final total = trueNegative + falsePositive;
    if (total == 0) {
      return 0.0; // No ground truth negatives
    }

    return trueNegative / total;
  }

  /// Calculate Accuracy
  ///
  /// Accuracy = (TP + TN) / (TP + TN + FP + FN)
  /// Range: [0, 1], higher is better
  static double accuracy(Uint8List predicted, Uint8List groundTruth) {
    if (predicted.length != groundTruth.length) {
      throw ArgumentError('Masks must have the same size');
    }

    int correct = 0;

    for (int i = 0; i < predicted.length; i++) {
      final pred = predicted[i] > 0 ? 1 : 0;
      final gt = groundTruth[i] > 0 ? 1 : 0;

      if (pred == gt) {
        correct++;
      }
    }

    return correct / predicted.length;
  }

  /// Calculate F1 Score (sama dengan Dice untuk binary segmentation)
  ///
  /// F1 = 2 * (Precision * Recall) / (Precision + Recall)
  /// Range: [0, 1], higher is better
  static double f1Score(Uint8List predicted, Uint8List groundTruth) {
    final prec = precision(predicted, groundTruth);
    final rec = recall(predicted, groundTruth);

    if (prec + rec == 0) {
      return 0.0;
    }

    return 2 * (prec * rec) / (prec + rec);
  }

  /// Calculate all metrics at once for efficiency
  ///
  /// Returns a map with all metrics:
  /// - dice: Dice coefficient
  /// - iou: Intersection over Union
  /// - precision: Positive Predictive Value
  /// - recall: Sensitivity
  /// - specificity: True Negative Rate
  /// - accuracy: Overall accuracy
  /// - f1: F1 score
  static Map<String, double> calculateAll(
      Uint8List predicted, Uint8List groundTruth) {
    if (predicted.length != groundTruth.length) {
      throw ArgumentError('Masks must have the same size');
    }

    int tp = 0, tn = 0, fp = 0, fn = 0;
    int intersection = 0, union = 0;

    for (int i = 0; i < predicted.length; i++) {
      final pred = predicted[i] > 0 ? 1 : 0;
      final gt = groundTruth[i] > 0 ? 1 : 0;

      if (pred == 1 && gt == 1) {
        tp++;
      } else if (pred == 0 && gt == 0) {
        tn++;
      } else if (pred == 1 && gt == 0) {
        fp++;
      } else if (pred == 0 && gt == 1) {
        fn++;
      }

      intersection += pred & gt;
      union += pred | gt;
    }

    final total = predicted.length;
    final predSum = tp + fp;
    final gtSum = tp + fn;

    // Calculate metrics
    final diceValue =
        (predSum + gtSum == 0) ? 1.0 : (2.0 * tp) / (predSum + gtSum);
    final iouValue = (union == 0) ? 1.0 : intersection / union;
    final precisionValue = (predSum == 0) ? 0.0 : tp / predSum;
    final recallValue = (gtSum == 0) ? 0.0 : tp / gtSum;
    final specificityValue = (tn + fp == 0) ? 0.0 : tn / (tn + fp);
    final accuracyValue = (tp + tn) / total;
    final f1Value = (precisionValue + recallValue == 0)
        ? 0.0
        : 2 * (precisionValue * recallValue) / (precisionValue + recallValue);

    return {
      'dice': diceValue,
      'iou': iouValue,
      'precision': precisionValue,
      'recall': recallValue,
      'specificity': specificityValue,
      'accuracy': accuracyValue,
      'f1': f1Value,
      'tp': tp.toDouble(),
      'tn': tn.toDouble(),
      'fp': fp.toDouble(),
      'fn': fn.toDouble(),
    };
  }

  /// Get confusion matrix
  ///
  /// Returns a map with:
  /// - tp: True Positives
  /// - tn: True Negatives
  /// - fp: False Positives
  /// - fn: False Negatives
  static Map<String, int> confusionMatrix(
      Uint8List predicted, Uint8List groundTruth) {
    if (predicted.length != groundTruth.length) {
      throw ArgumentError('Masks must have the same size');
    }

    int tp = 0, tn = 0, fp = 0, fn = 0;

    for (int i = 0; i < predicted.length; i++) {
      final pred = predicted[i] > 0 ? 1 : 0;
      final gt = groundTruth[i] > 0 ? 1 : 0;

      if (pred == 1 && gt == 1) {
        tp++;
      } else if (pred == 0 && gt == 0) {
        tn++;
      } else if (pred == 1 && gt == 0) {
        fp++;
      } else if (pred == 0 && gt == 1) {
        fn++;
      }
    }

    return {
      'tp': tp,
      'tn': tn,
      'fp': fp,
      'fn': fn,
    };
  }
}
