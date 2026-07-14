# 오리파 리빌/봉인팩 — 세션 핸드오프 (다음 세션 콜드스타트용)

> **이 문서만 읽으면 바로 이어서 진행 가능.** 이번 세션에서 팩 외형을 10+회 반려·정정하며 결정을 잠갔다.
> **§3 잠긴 결정을 다시 열지 말 것**(반복 금지). 상세 계약은 3개 스펙 문서(§7) 참조.
> 최종 갱신: 2026-07-14. 최신 커밋: `e87be13`.

---

## 1. 궁극 목표 (무엇을 만드는가)
오리파(오프라인 매장 카드 뽑기) 앱의 **리빌 경험**: 프리미엄 **봉인 포일팩**을 뜯으면 **카드가 올라오고**, 등급에 따라 연출이 달라지는 "뽑고 싶은" 경험.
- **NORMAL 경로**: 담백 — 절취 → 카드 뒷면 상승 → 플립 → 앞면.
- **HIT 경로**(rare/hit/jackpot): 절취 → 뒷면 상승 + 금빛 아우라 → 탭 → 전체 암전 → 문구 1개씩 → 정적 → 중심광 → 빛 폭발 → 앞면 HERO 첫 등장.
- **Phase 1** = v4 핵심 안무·기능 구현. **Phase 2** = 실기기 사운드·햅틱·입자·타이밍·광량 튜닝.

## 2. 최종 산출물 (완성 정의)
1. **팩 = 플랫폼 템플릿 카탈로그 3종**(네이비·골드 / 홀로 포일 / 실버 메탈릭). 사장님이 선택 + 매장 로고·오리파명 오버레이. 승인 템플릿 추후 추가 가능.
2. **3종 팩 자산**: 고해상도·실제 투명 알파, **공통 실루엣 1개 + 재질 3개**, 4레이어(`base`/`open_body`/`top_strip`/`mouth_shadow`).
3. **Flutter 리빌**: 자산 4레이어 합성 → 절취 → 카드 상승 → NORMAL/HIT 분기 → (HIT) 암전·문구·빛폭발·HERO. 미세 3D·이동 sheen·아우라는 런타임 레이어.
4. **파트너센터**: 팩 편집·미리보기·검수 제출 UI (`PackVisualConfig`).
5. **백엔드**: `PackVisualConfig` 모델 + 관리자 검수 + LIVE 버전 스냅샷. (Codex 상의 대상)
6. 기준선 IPA → 실기기 녹화 → 4개 조정 튜닝.

---

## 3. 잠긴 결정 (LOCKED — 다시 열지 말 것)
1. **팩 = 3종 카탈로그**(네이비/홀로/실버). 단일 팩 확정 아님. 파트너센터엔 항상 3개 노출.
2. **팩 외형을 코드(HTML/CSS/SVG/CustomPainter)로 손제작 금지** — 4회 반려 확정. 팩 그래픽 = 이미지 생성/디자이너 산출물. Flutter는 레이어 합성·애니만.
3. **생성 배경 = 투명 PNG(실제 알파)**. 회색 배경 폐기. **가짜 투명(체크무늬 구운 RGB) 금지** — 반드시 알파 실측. 밝은 팩(실버)은 밝은 배경 금지(누끼 실패) → 투명/어두운 대비 배경.
4. **실루엣 1개 마스터 + 재질 3개.** 독립 랜덤 3장 생성 금지(구조 어긋남) → 한 마스터의 재질 변형(img2img/리컬러/seed+material swap). 저해상도 3×3 합본 크롭 = **목업 전용, 앱 자산 금지**.
5. **자산 조건**: 각 템플릿 독립, 원본 ≥1200×1985, 최종 780×1290(@3x, 비율 0.605). 이미지에 **굽지 말 것**: 그림자·검은무대·글자·로고·이동 반사광.
6. **3D = 정면 유지 + ±2~3° 미세 원근만.** 큰 기울기·강한 blur 금지. 두께감 = 측면 림라이트+작은 바닥그림자+이동 sheen(전부 런타임).
7. **팩 전면 배치**(높이 %): `0–30% 완전 비움`(절취·카드 상승 공간) / `32–55% 매장 로고` / `62–69% POKEFOLIO` / `72–84% 오리파명` / `90–100% 하단 크림프 비움`. 텍스트·로고·카드뒷면·이동sheen·아우라 = **전부 Flutter 오버레이**(이미지에 안 굽음). 번호는 팩에 안 그림(CTA 표시).
8. **PackVisualConfig(사장님 외형) ↔ RevealDescriptor/RevealPolicy(HIT·아우라·연출 강도) 절대 분리.** 사장님=외형만. HIT여부·아우라 tier·암전·빛폭발=서버/관리자. 같은 오리파는 **개봉 전 NORMAL/HIT/GRADED 동일 팩**(결과별 차등=스포일러 금지).
9. **리빌 계약**(불변): 리빌 경로 = `RevealDescriptor`의 **path 축**(intensity로 추론 금지 — 정책발급 path 필드 step3에서 추가 예정). `markRevealStarted`=플립 시작 / `markRevealed`=HERO 완전노출 후. `drawId`·exactly-once·recovery(committed/revealed). reduceMotion=축소하되 결과 직행 금지.
10. **운영 화면 = 파트너센터 UI**(preview.html), **구현 구조 = 4레이어**(layers). 둘 섞지 말 것.

---

## 4. 지금까지 한 것 (현재 상태)
### ✅ 완료
- **Step 1 기술 기반**(`47d4dfb`): `/oripa/draw` route fade + **route completed 후 추출 시작**(고정 딜레이 아님) + **가로 드래그 절취** + 60/82% 햅틱 + **중심 고정**(테스트로 증명). 파일 `oripa_draw_screen.dart`.
- **리빌 v4 스펙 정합성**(`3cfcdde`): 경로/아우라 2축, CTA 이중입력, reduceMotion, 저장소 스토리보드.
- **팩 템플릿 카탈로그 설계**(`1c95ef5`~`e893fa6`): `PackVisualConfig`, 파트너센터 미리보기 목업, 안전영역, 자산 조건·알파QA·3D·공통 마스터 구조 lock.
- **봉인팩 자산 기반 리빌 실구현**(`e87be13`): `OripaSealedPack` 절차적→자산 기반 재작성. 네이비 4레이어 합성, 상단 절취 애니(top_strip 위로 찢김→개봉구 노출), 미세 3D, 하단 브랜딩 오버레이, 회색배경 없음. pubspec 등록. **골든 3종 재생성 + 반응형·중심불변 7/7 테스트 통과, analyze 클린.** 실기기급 모션 캡처 확인.

### ⚠️ 프로비저널 / 미완
- **네이비 자산 = 975px 프로비저널**(`~/Downloads/f7fd398a-...png` = 형의 투명 네이비인데 실제론 RGB 체크무늬 가짜투명 → rembg 매트해서 씀). **최종은 1200↑ 재출력 필요.**
- **홀로·실버 자산 없음** — 형이 이미지 툴로 생성해야 함(Claude 생성 불가). `OripaSealedPack.assetDir`은 현재 네이비 하드코딩.
- **Step 2 미착수**: 카드 뒷면 상승·아우라·NORMAL/HIT 분기·암전·문구·빛폭발.
- 파트너센터 UI·백엔드 `PackVisualConfig` = 목업/스펙만(실구현 X).

---

## 5. 다음 세션 To-Do (순서)
0. **입력 대기(형)**: 홀로·실버 + 1200↑ 네이비 = **같은 실루엣의 재질 변형, 투명·고해상도**. 저장 위치 알려주면 진행.
1. 각 마스터 → 레이어 파생: `python3 front/tool/oripa_pack/pack_layers.py <master.png> front/assets/oripa/packs/<navy|holo|silver>/ --matte`
2. **알파 QA**: `python3 front/tool/oripa_pack/qa_alpha.py <base.png>` → 모서리·톱니사이 alpha=0, 검정/흰색/빨강 합성 엣지 검수. 프린지 있으면 매트 재작업.
3. `pubspec.yaml`에 `assets/oripa/packs/holo/`·`silver/` 등록. `OripaSealedPack`에 **templateId→assetDir 배선**(현재 네이비 하드코딩 제거).
4. 골든 3종 재생성(`flutter test test/oripa/oripa_sealed_pack_golden.dart --update-goldens`).
5. **Step 2**: `card_back`(Flutter 레이어) 개봉구에서 상승 + 팩 하강 퇴장 + 이동 sheen + 림라이트. `reveal_view.dart` 배선.
6. **NORMAL/HIT 분기**: `reveal_models.dart`에 정책발급 `RevealPath` 축 추가(불변식 테스트) → HIT는 암전·문구(단일)·빛폭발·HERO / NORMAL은 담백 플립.
7. 파트너센터 편집·미리보기·검수 UI 실구현 + 백엔드 `PackVisualConfig`(검수·LIVE 버전) — **Codex 상의**(CLAUDE.md).
8. 기준선 IPA → 실기기 녹화 → 4개 조정 튜닝.

---

## 6. 자산 파이프라인 (재사용 도구 = repo에 이관됨)
- `front/tool/oripa_pack/pack_layers.py` — 마스터 PNG → 4레이어(base/open_body/top_strip/mouth_shadow) + 알파 QA. `--matte`면 rembg로 배경 제거.
- `front/tool/oripa_pack/qa_alpha.py` — 알파 실측 + 검정/흰색/빨강 3배경 엣지 합성 검수.
- 의존: `python3 -m pip install --user rembg onnxruntime pillow numpy` (이번 세션에 설치됨).
- 레이어 규칙: `strip_h = mouth_h = base 높이의 14%`(닫힘 정합). top_strip은 base 상단 14%, open_body는 상단 14% 어둡게(알파 유지).

## 7. 참조 (스펙 3종 + 코드/자산 맵)
- **스펙**: `docs/ORIPA_REVEAL_PHASE1.md`(리빌 v4 계약) · `docs/ORIPA_PACK_ASSET.md`(자산 조건·레이어·QA·3D·공통 마스터 §4.5) · `docs/ORIPA_PACK_TEMPLATE.md`(카탈로그·PackVisualConfig·안전영역·파트너센터).
- **코드**: `front/lib/features/oripa/draw/oripa_sealed_pack.dart`(자산 팩 위젯) · `draw/oripa_draw_screen.dart`(스테이지·절취·게이팅) · `draw/reveal_view.dart`(상태머신) · `data/reveal_models.dart`(RevealDescriptor/intensity/정책) · `data/oripa_session.dart`(ActiveDraw·confirmDraw).
- **자산**: `front/assets/oripa/packs/navy/{base,open_body,top_strip,mouth_shadow}.png`(프로비저널).
- **테스트**: `front/test/oripa/oripa_sealed_pack_golden.dart`(골든3+반응형3+중심불변1). 자산 골든은 `precacheImage` 필요.
- **파트너센터 목업**: 이번 세션 scratchpad(`partner/preview.html`) — 세션 소멸. 필요시 재작성(스펙은 ORIPA_PACK_TEMPLATE.md).
- **커밋 흐름**: `4850141`(v4)→`3cfcdde`(2축)→`47d4dfb`(Step1)→카탈로그/자산 docs→`e87be13`(자산팩 실구현).
