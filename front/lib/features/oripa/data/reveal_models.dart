/// STEP 2 결과 리빌 데이터층 (2026-07-10, spec §B).
/// 개봉 확정 후 상품 메타데이터를 비트 단위로 순차 공개. 번호=확정형/봉인형=추측형.
/// 시각 엔진(RevealConfig)과 정책(RevealPolicy)은 분리. `RevealDescriptor`는 draw와
/// 원자 발급(뽑기 전 사전 노출 금지) — mock은 클라 파생하되 구조는 서버 발급형과 동일.
library;

import 'oripa_prizes.dart';

/// 리빌 프로파일 — 연출 의미·단서 순서 결정 (비트 배열 고정, spec §B-2).
enum RevealProfile {
  numberedConfirmRaw, // 헤더 + SET·CONDITION·RARITY·NAME (4 clue) + HERO
  numberedConfirmGraded, // 헤더 + SET·COMPANY·GRADE·RARITY·NAME (5 clue) + HERO
  sealedMysteryRaw, // (향후) SET·CONDITION·RARITY·NAME (4) + HERO
  sealedMysteryGraded, // (향후) SET·COMPANY·GRADE·RARITY·NAME (5) + HERO
  packConfirm, // CATEGORY·NAME (2) + HERO
  goodsConfirm, // CATEGORY·NAME (2) + HERO
}

/// 단서 비트 종류 (각 1비트, 비트 묶기 금지).
enum RevealClueKind { condition, gradingCompany, gradeValue, rarity, set, name, category }

class RevealClue {
  final RevealClueKind kind;
  final String text;
  const RevealClue(this.kind, this.text);
}

/// 연출 강도 — 효과(빛/사운드/햅틱)만 좌우. 비트 수·탭 수엔 영향 없음.
enum RevealIntensity { normal, rare, hit, jackpot }

/// 리빌 경로 축 (LOCKED §3-9) — **intensity와 독립 발급**. 렌더러 추론 금지.
/// normal = 담백 플립 / hit = 아우라·확회전·암전·문구·플래시·HERO (rare 이상 공통).
/// ★effectsEnabled/maxIntensity(운영 플래그)는 intensity만 낮출 뿐 경로를 못 바꾼다.
enum RevealPath { normal, hit }

/// draw 결과와 원자 발급되는 리빌 지시서. clues = 공개 순서(HERO stage는 별도).
class RevealDescriptor {
  final RevealProfile profile;
  final String? openingHeader; // 번호형: "47번 당첨" / 봉인형: null (탭 불필요 헤더)
  final List<RevealClue> clues; // 가속 대상 = clue 비트만. HERO는 미포함.
  final ImageRef heroImageRef; // 최종 HERO stage 이미지 (= prize.imageRef)
  final RevealIntensity intensity;
  final RevealPath path; // ★경로 분기의 단일 진실원 — 정책이 intensity와 독립 발급
  const RevealDescriptor({
    required this.profile,
    this.openingHeader,
    required this.clues,
    required this.heroImageRef,
    required this.intensity,
    required this.path,
  });

  /// 가속 가능 clue 비트 수 (프로파일 내 고정, HERO 제외). spec §B-6.5.
  int get clueBeatCount => clues.length;
}

/// 강도 발급 정책 — RevealConfig(모션 표현)와 **분리**. mock=중앙 정책, 미래=서버 권위.
/// ★교환P는 사장님이 정하므로 클라가 교환P만 보고 JACKPOT 자동 결정 금지 → 정책이 발급.
class RevealPolicy {
  final bool effectsEnabled;
  final RevealIntensity maxIntensity;
  const RevealPolicy({
    this.effectsEnabled = true,
    this.maxIntensity = RevealIntensity.jackpot,
  });

  // 교환P 임계 (데이터 값 — 미래엔 서버 운영정책이 대체).
  static const int rareAt = 10000;
  static const int hitAt = 50000;
  static const int jackpotAt = 200000;

  RevealIntensity intensityFor(int exchangePoints) {
    if (!effectsEnabled) return RevealIntensity.normal;
    final RevealIntensity raw;
    if (exchangePoints >= jackpotAt) {
      raw = RevealIntensity.jackpot;
    } else if (exchangePoints >= hitAt) {
      raw = RevealIntensity.hit;
    } else if (exchangePoints >= rareAt) {
      raw = RevealIntensity.rare;
    } else {
      raw = RevealIntensity.normal;
    }
    return raw.index <= maxIntensity.index ? raw : maxIntensity;
  }

  /// 경로 발급 — **intensity 파생 금지**(2026-07-15 반려 교훈). 교환P 임계 직접 판정이라
  /// effectsEnabled=false·maxIntensity 캡이 걸려도 HIT 경로는 유지된다(연출 광량만 감소).
  /// mock=클라 판정, 미래=서버가 draw와 원자 발급(step 백엔드에서 교체).
  RevealPath pathFor(int exchangePoints) =>
      exchangePoints >= rareAt ? RevealPath.hit : RevealPath.normal;
}

/// mock 중앙 정책. 미래: 서버 발급으로 교체.
const RevealPolicy kMockRevealPolicy = RevealPolicy();

/// 저사양 대체 — 접근성(reduceMotion)과 **별개** 개념.
enum EffectsQuality { low, standard }

/// 리빌 튜닝값 (하드코딩 금지 원칙 → 여기 기본값, 실기기 조정). 레퍼런스 2·4 문법 반영.
class RevealConfig {
  final int openingLockMs; // 첫 오프닝 헤더 입력 잠금
  final int beatDwellMs; // clue 비트 표시 유지
  final int pauseBetweenBeatsMs; // ★정적 구간 = 긴장 핵심
  final int heroHoldMinMs; // HERO 완전 표시 후 최소 유지(단축 불가)
  final bool tapAdvance; // clue 비트 탭 가속 허용
  final bool reduceMotion; // OS 접근성: 애니 이동·회전 축소
  final EffectsQuality effectsQuality; // 기기 성능: 파티클·블러·광원 축소
  const RevealConfig({
    this.openingLockMs = 900,
    this.beatDwellMs = 650,
    this.pauseBetweenBeatsMs = 260,
    this.heroHoldMinMs = 700,
    this.tapAdvance = true,
    this.reduceMotion = false,
    this.effectsQuality = EffectsQuality.standard,
  });

  RevealConfig copyWith({
    int? openingLockMs,
    int? beatDwellMs,
    int? pauseBetweenBeatsMs,
    int? heroHoldMinMs,
    bool? tapAdvance,
    bool? reduceMotion,
    EffectsQuality? effectsQuality,
  }) {
    return RevealConfig(
      openingLockMs: openingLockMs ?? this.openingLockMs,
      beatDwellMs: beatDwellMs ?? this.beatDwellMs,
      pauseBetweenBeatsMs: pauseBetweenBeatsMs ?? this.pauseBetweenBeatsMs,
      heroHoldMinMs: heroHoldMinMs ?? this.heroHoldMinMs,
      tapAdvance: tapAdvance ?? this.tapAdvance,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      effectsQuality: effectsQuality ?? this.effectsQuality,
    );
  }
}

const RevealConfig kDefaultRevealConfig = RevealConfig();

/// draw 결과 → RevealDescriptor 원자 발급 (mock 클라 파생, 구조는 서버 발급형과 동일).
/// [number] != null → 번호 오리파(확정형, 오프닝 헤더). null → 봉인형(추측형, 향후).
/// 프로파일·clue는 sealed 타입 **패턴 매칭**으로 결정(exhaustive).
RevealDescriptor buildRevealDescriptor(
  OripaPrize prize, {
  int? number,
  RevealPolicy policy = kMockRevealPolicy,
}) {
  final header = number != null ? '$number번 당첨' : null;
  final intensity = policy.intensityFor(prize.exchangePoints);
  final path = policy.pathFor(prize.exchangePoints); // intensity와 독립 발급
  final hero = prize.imageRef;

  switch (prize) {
    case RawCardPrize p:
      return RevealDescriptor(
        profile: number != null
            ? RevealProfile.numberedConfirmRaw
            : RevealProfile.sealedMysteryRaw,
        openingHeader: header,
        clues: [
          RevealClue(RevealClueKind.set, p.setDisplayName),
          const RevealClue(RevealClueKind.condition, 'RAW'),
          RevealClue(RevealClueKind.rarity, p.rarityCode.label),
          RevealClue(RevealClueKind.name, p.displayName),
        ],
        heroImageRef: hero,
        intensity: intensity,
        path: path,
      );
    case GradedCardPrize p:
      return RevealDescriptor(
        profile: number != null
            ? RevealProfile.numberedConfirmGraded
            : RevealProfile.sealedMysteryGraded,
        openingHeader: header,
        clues: [
          RevealClue(RevealClueKind.set, p.setDisplayName),
          RevealClue(RevealClueKind.gradingCompany, p.gradingCompany.label),
          RevealClue(RevealClueKind.gradeValue, p.gradeValue),
          RevealClue(RevealClueKind.rarity, p.rarityCode.label),
          RevealClue(RevealClueKind.name, p.displayName),
        ],
        heroImageRef: hero,
        intensity: intensity,
        path: path,
      );
    case SealedPackPrize p:
      return RevealDescriptor(
        profile: RevealProfile.packConfirm,
        openingHeader: header,
        clues: [
          const RevealClue(RevealClueKind.category, '미개봉 팩'),
          RevealClue(RevealClueKind.name, p.displayName),
        ],
        heroImageRef: hero,
        intensity: intensity,
        path: path,
      );
    case GoodsPrize p:
      return RevealDescriptor(
        profile: RevealProfile.goodsConfirm,
        openingHeader: header,
        clues: [
          const RevealClue(RevealClueKind.category, '굿즈'),
          RevealClue(RevealClueKind.name, p.displayName),
        ],
        heroImageRef: hero,
        intensity: intensity,
        path: path,
      );
  }
}
