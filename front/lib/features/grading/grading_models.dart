class DeductionReason {
  final String id;
  final String type;
  final String label;
  final String side;
  final String position;
  final String severity;
  final double confidence;
  final double penalty;
  final List<double>? bbox;
  final String explanation;

  DeductionReason({
    required this.id,
    required this.type,
    required this.label,
    required this.side,
    this.position = '',
    this.severity = 'minor',
    this.confidence = 1.0,
    this.penalty = 0.0,
    this.bbox,
    this.explanation = '',
  });

  factory DeductionReason.fromJson(Map<String, dynamic> json) {
    return DeductionReason(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      side: json['side']?.toString() ?? '',
      position: json['position']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'minor',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      penalty: (json['penalty'] as num?)?.toDouble() ?? 0.0,
      bbox: (json['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      explanation: json['explanation']?.toString() ?? '',
    );
  }
}

class DefectRegion {
  final String type;
  final List<double> bbox;
  final String side;
  final String color;

  DefectRegion({
    required this.type,
    required this.bbox,
    required this.side,
    this.color = '#E74C3C',
  });

  factory DefectRegion.fromJson(Map<String, dynamic> json) {
    return DefectRegion(
      type: json['type']?.toString() ?? '',
      bbox: (json['bbox'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [0, 0, 0, 0],
      side: json['side']?.toString() ?? '',
      color: json['color']?.toString() ?? '#E74C3C',
    );
  }
}

class GradingResult {
  final double centeringScore;
  final double cornerScore;
  final double surfaceScore;
  final double whiteningScore;
  final double edgeScore;
  final double totalScore;
  final double totalScoreDisplay;
  final double weightedScore;
  final String grade;
  final String gradeColor;
  final bool heavyWhitening;
  final bool hasMajorDefect;
  final bool retakeRequired;
  final String retakeReason;
  final String captureQuality;
  final bool screenSuspected;
  final String screenSuspectReason;
  final double detectionConfidence;
  final bool identityVerified;
  final String centeringRatio;
  final String centeringDetail;
  final String cornerDetail;
  final String surfaceDetail;
  final String whiteningDetail;
  final String edgeDetail;
  final List<DeductionReason> deductionReasons;
  final List<DefectRegion> defectRegions;

  GradingResult({
    required this.centeringScore,
    required this.cornerScore,
    required this.surfaceScore,
    required this.whiteningScore,
    required this.edgeScore,
    required this.totalScore,
    required this.totalScoreDisplay,
    required this.weightedScore,
    required this.grade,
    required this.gradeColor,
    required this.heavyWhitening,
    required this.hasMajorDefect,
    required this.retakeRequired,
    required this.retakeReason,
    required this.captureQuality,
    this.screenSuspected = false,
    this.screenSuspectReason = '',
    required this.detectionConfidence,
    required this.identityVerified,
    required this.centeringRatio,
    required this.centeringDetail,
    required this.cornerDetail,
    required this.surfaceDetail,
    required this.whiteningDetail,
    required this.edgeDetail,
    required this.deductionReasons,
    required this.defectRegions,
  });

  factory GradingResult.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v, [double fallback = 0.0]) =>
        v is num ? v.toDouble() : fallback;
    return GradingResult(
      centeringScore: asDouble(json['centeringScore']),
      cornerScore: asDouble(json['cornerScore']),
      surfaceScore: asDouble(json['surfaceScore']),
      whiteningScore: asDouble(json['whiteningScore']),
      edgeScore: asDouble(json['edgeScore']),
      totalScore: asDouble(json['totalScore']),
      totalScoreDisplay: asDouble(json['totalScoreDisplay']),
      weightedScore: asDouble(json['weightedScore']),
      grade: json['grade']?.toString() ?? 'C',
      gradeColor: json['gradeColor']?.toString() ?? '#95A5A6',
      heavyWhitening: json['heavyWhitening'] == true,
      hasMajorDefect: json['hasMajorDefect'] == true,
      retakeRequired: json['retakeRequired'] == true,
      retakeReason: json['retakeReason']?.toString() ?? '',
      captureQuality: json['captureQuality']?.toString() ?? 'good',
      screenSuspected: json['screenSuspected'] == true,
      screenSuspectReason: json['screenSuspectReason']?.toString() ?? '',
      detectionConfidence: asDouble(json['detectionConfidence'], 1.0),
      identityVerified: json['identityVerified'] == true,
      centeringRatio: json['centeringRatio']?.toString() ?? '',
      centeringDetail: json['centeringDetail']?.toString() ?? '',
      cornerDetail: json['cornerDetail']?.toString() ?? '',
      surfaceDetail: json['surfaceDetail']?.toString() ?? '',
      whiteningDetail: json['whiteningDetail']?.toString() ?? '',
      edgeDetail: json['edgeDetail']?.toString() ?? '',
      deductionReasons: (json['deductionReasons'] as List?)
              ?.map((e) => DeductionReason.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      defectRegions: (json['defectRegions'] as List?)
              ?.map((e) => DefectRegion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
