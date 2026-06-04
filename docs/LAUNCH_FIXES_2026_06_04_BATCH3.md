# Launch Fixes — Batch 3 (2026-06-04, 출시 직전)

> 디바이스 테스트 중 발견. 프론트 변경은 다음 IPA, 백엔드 변경은 1회 배포 후 IPA.
> 진행: **하나씩** 처리하고 각 항목 체크 + 커밋 해시 기록.

---

## B3-1. 실거래가 도메인 검증 (★최우선, front + backend) — [x] DONE

**현상**: 희망가 725,100원 거래에서 실거래가 **99,999원**(≈13.8%) 입력해도 그대로 기록됨.
지금 검증 = 비어있지 않음 / 숫자 / 0보다 큼 수준뿐. 이 값이 시세/실거래 가격엔진에 들어가면 오염.

**핵심**: 단순 숫자 검증 X → **도메인 검증**. 그리고 **프론트만이 아니라 백엔드 최종 게이트**(API 직접 호출 방어).

### 정책 (리젝 규칙)
| 항목 | 정책 |
|---|---|
| 빈 값 / 숫자 아님 | 리젝 |
| 1,000원 미만 | 리젝 |
| 100원 단위 아님 | 리젝 (단, 희망가/시세와 정확히 일치하면 신뢰 → 통과) |
| 기준가의 하한 미만 | 리젝 |
| 기준가의 상한 초과 | 리젝 |
| 1,000,000,000원 이상 | 리젝 (절대 상한) |

### 기준가(reference) 우선순위 + 밴드
1. **앱 시세 (KO_ESTIMATED)** 있으면 → 밴드 **0.4 ~ 1.8**
2. 없으면 **희망가/판매가 (listing/bid price)** → 밴드 **0.5 ~ 1.5**
3. 둘 다 없으면 → 단위 규칙 + 절대 상한만

> 예: 기준 725,100원 → 시세 밴드 약 290,040 ~ 1,305,180 / 희망가 밴드 362,550 ~ 1,087,650.
> 99,999원은 양쪽 다 하한 미만 → 리젝.

### 적용 위치
- **프론트** (trade_settlement_sheet.dart `_submit`): 희망가(agreedPrice) 기준 밴드 0.5~1.5 + 단위 규칙. 버튼 누르기 전 즉시 에러 문구.
  - "이 금액이 맞아요"(mode 0) = 희망가 그대로 → 신뢰(검증 통과).
- **백엔드** (TradeServiceImpl `submitSettlement` + `submitBuySettlement`): 시세 우선 풀 검증. 위반 시 **400** 리턴 → 저장 X.
  - SALE 기준가 = post.getCardId() 시세 ?? post.getPrice(). BUY = order.getCardId() 시세 ?? order.getBidPrice().

### UX 문구
- 너무 낮음: `입력한 금액이 희망가보다 너무 낮아요.\n실제 거래 금액을 다시 확인해주세요.`
- 너무 높음: `입력한 금액이 희망가보다 너무 높아요.\n실제 거래 금액을 다시 확인해주세요.`
- 100원 단위: `거래 금액은 100원 단위로 입력해주세요.`
- 1,000원 미만: `거래 금액은 1,000원 이상 입력해주세요.`

**주의**: 현재 모델에서 "거래 완료"(상태) 와 "실거래가 입력"은 **별개 단계**. 완료는 가격 입력 전에 이미 발생(시스템 메시지 포함). 따라서 본 검증은 **실거래가 submit** 을 막아 데이터 오염만 차단(완료 자체는 분리). 사용자 플로우차트의 "상태 변경 금지/시스템 메시지 금지"는 가격≠완료 구조라 해당 없음.

---

## B3-2. 채팅 키보드 dismiss — [x] DONE
**현상**: 채팅방에서 다른 곳 탭해도 키보드가 안 내려감.
**수정**: chat_room_screen body 를 `GestureDetector(onTap: FocusScope.of(context).unfocus, behavior: opaque)` 로 감싸 빈 영역 탭 시 unfocus.

---

## B3-3. 재초대 후 상단 배너 안 사라짐 — [x] DONE
**현상**: 상대가 나가면 "상대방이 채팅방을 나갔어요. 메시지를 보내면 다시 초대돼요." 배너 노출. 메시지 보내면 재초대는 되는데 **배너가 그대로**.
**수정**: 메시지/이미지 전송 성공 후 conversation-state 재조회(`_loadConversationState`) → otherLeft 갱신 → 배너 사라짐.

---

## B3-4. 상태 칩 라벨 통일 — [x] DONE
**현상**: RESERVED 상태가 **판매=예약 중 / 구매=거래 중** 으로 불일치. (게다가 SALE 칩 '예약 중' vs SALE 시트 타일 '거래 중' 도 자기모순)
**수정**: SALE 칩 RESERVED `예약 중` → `거래 중` 으로 통일 (시트·구매와 일치). chat_room_screen `_buildTradeStatusChip`.

---

## B3-5. 구매 "호가 취소" vs 판매 일관성 — [x] DONE
**현상**: 구매 상태 시트엔 "구매 호가 취소", 판매엔 "판매글 삭제". 사용자: 왜 구매만 취소가 있냐.
**수정**: 둘 다 "삭제" 용어로 통일 — 구매 `구매 호가 취소` → `구매 호가 삭제` + confirm 문구 삭제 톤. (기능은 동일 = 호가 내림). chat_room_screen.

---

## B3-6. 알림 항목 상태 표시 — [x] DONE
**현상**: 알림/인박스 항목("구매 거래가 완료되었습니다")에 거래 상태 표시가 없음. (Image #30)
**수정**: 알림 리스트 아이템에 상태 칩(거래중/거래완료 등) 노출. 해당 위젯 위치 확인 후 적용.

---

## B3-7. 거래 고지문 들여쓰기/줄바꿈 — [x] DONE
**현상**: 거래 상세 고지 박스(포켓폴리오는 직거래 연결…) 줄바꿈 시 들여쓰기 안 맞아 줄이 이상. (Image #31)
**수정**: `Row[Icon, gap, Expanded(Text)]` 구조로 행잉 인덴트 — 둘째 줄부터 텍스트 컬럼에 정렬. 아이콘은 top 정렬.

---

## B3-8. "앱 정보" 기본 라이선스 화면 정리 — [x] DONE
**현상**: MY > "앱 정보" 탭 → Flutter 기본 `showAboutDialog` → "View licenses" → 기본 `LicensePage`.
"Powered by Flutter" + 영문 패키지 100여 개 raw 리스트(_flutterfire_internals, abseil-cpp, angle …) 그대로 노출 → 출시 앱에 부적절. (Image #32, #33)
**위치**: profile_screen.dart:241-252 (`showAboutDialog`).
**제약**: OSS 라이선스 고지는 **법적으로 제거 불가**(MIT/BSD/Apache attribution 의무). 표현만 정돈.
**수정 방향**:
- "앱 정보" → **커스텀** 다이얼로그/화면: 로고·이름·v1.0.0·© 2026 PokeFolio + 비공식 팬서비스 고지. "Powered by Flutter"/raw 리스트 **메인 노출 제거**.
- "오픈소스 라이선스"를 **별도 메뉴 항목**으로 격하 → `showLicensePage(applicationName/version/legalese 지정)` 으로 상단 브랜딩. raw 패키지 리스트는 법적 고지로 유지하되 의도된 위치에.
- 버전 문자열 하드코딩(v1.0.0) — 가능하면 package_info_plus 로 동기화(선택).

---

## B3-9. 채팅 사진 여러 장 전송 — [x] DONE
**현상**: 채팅방 이미지가 "1회 1장"(pickImage)이라 앨범에서 여러 장 보내기 불가/막힘. (Image #34)
**수정**: 앨범 옵션 → `pickMultiImage`(최대 5장) 순차 업로드. 각 업로드 STOMP echo 가 IMAGE 메시지로 순서대로 도착. 카메라는 단일 유지. chat_room_screen `_pickAndUploadMultiImages`.

---

## B3-10. 프사 없는/실패 사용자 챗 아바타 깨짐 — [x] DONE
**현상**: 프로필 이미지 없는 사용자 아바타가 챗(리스트/방)에서 깨진 글리프로 표시. (Image #35)
**원인**: 백엔드는 프사 없으면 null/"" 반환(정상 → UserAvatar 기본아이콘). 깨짐은 AuthImage ①로딩 스피너가 작은 아바타에서 깨져 보임 ②다운로드가 비-이미지 작은 바이트(에러본문) 반환 시 Image.memory 가 깨진 글리프 렌더(errorBuilder 미발동).
**수정**: auth_image.dart — 로딩 상태를 중립 placeholder로, bytes `< 100B` 도 에러 처리 → errorBuilder(UserAvatar 기본 사람아이콘) 폴백 보장.

---

## B3-1 보강 (Codex 리뷰 반영) — [x] DONE
**Codex BLOCKER**: 프론트 `_validatePrice` 가 희망가(agreedPrice)만 기준 0.5~1.5 밴드 → 희망가≪시세 카드에서 **정상값 false-positive 차단**.
**추가 발견**: `ReturnData.badRequest` 는 controller return 값이라 **HTTP 200 바디(status=fail)** 로 내려옴(상태코드 아님). 프론트 _submit 이 status 미확인 → 백엔드 거부를 **성공으로 오인**(토스트 "기록됐어요").
**수정**: 프론트 밴드 제거(단위 검증만), `_submit` 이 `res['status'] != 'success'` 면 `res['message']`(백엔드 시세 밴드 사유) 노출. 백엔드가 시세 기준 최종 판정.

---

## B3-11. 프사 변경 실패 사유 미노출 ("무조건 안돼") — [x] DONE
**현상**: 프로필 사진 변경 실패 시 사유 없이 "사진 변경에 실패했어요"만. (사용자: 이유 알려달라)
**원인**: edit_nickname `_pickAndUploadImage` 의 `catch(_)` 가 백엔드 ResponseStatusException 사유(400 "이미지 파일만"/413 "5MB"/403 "정지") 를 통째로 삼킴. + postMultipart 가 filename=field명("file", 무확장자)으로 보내 octet-stream → 일부 검증 거부 가능성.
**수정**: ① DioException → `e.response.data['message']` 사유 노출 ② postMultipart 실제 파일명(확장자) 사용 → contentType 정상화(잠재 실패원인 제거). 실제 root cause 는 노출된 사유로 디바이스에서 확인.

---

## B3-12. 이미지 5MB 일관 + 압축 확인 — [x] DONE
**확인**: 채팅 `pickImage(maxWidth 1600,q80)` / 프사 `pickImage(maxWidth 1024,q85)` → image_picker 가 업로드 전 **다운스케일+재인코딩**. 44MP·5.8MB 원본도 수백 KB로 압축 → 5MB 한도 거의 안 닿음(원본 크기 무관).
**수정(일관화)**: 채팅 클라 `_kMaxImageBytes` 10MB→5MB, 채팅 백엔드 `MAX_IMAGE_BYTES` 10MB→5MB, 프사 클라 5MB 가드 추가. (프사 백엔드 이미 5MB.) Spring servlet max-file-size=10MB 는 헤더룸으로 유지 → 핸들러 5MB 메시지가 먼저 발동.

---

## 진행 로그
- (작성) 2026-06-04 — 항목 7개 확정.
- (추가) 2026-06-04 — B3-8 앱 정보/라이선스 (총 8개).
- (추가) 2026-06-04 — B3-9 다중 사진 + B3-10 아바타 깨짐 (총 10개).
- (추가) 2026-06-04 — Codex 리뷰 반영(B3-1 보강) + B3-11 프사 사유 + B3-12 5MB 일관 (총 12개). 백엔드=B3-1·B3-12(채팅한도), 나머지 프론트.
