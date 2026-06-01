# 계정 탈퇴 정책 (DELETION_POLICY)

App Review 5.1.1 대응 + P2P 거래 환경 분쟁 증거 보존을 모두 만족하는 **soft delete + PII 마스킹** 정책.

## 원칙

1. **앱 안에서 사용자가 직접 탈퇴 가능** (Apple 요구사항)
2. **PII는 즉시 마스킹** (이메일/닉네임/프로필 이미지)
3. **분쟁/운영 증거 데이터는 보존** ("탈퇴한 사용자"로 표시)
4. **재로그인 차단** — Google 같은 외부 식별자(googleId)는 유지해서 같은 Google 계정으로 재가입 못 하게 함
5. **30일 grace period 없음** — 즉시 탈퇴. (필요 시 v1.1+에서 도입)

## 엔티티별 처리 정책

| 엔티티 | 처리 | 비고 |
|---|---|---|
| `users` | nickname → `"탈퇴한 사용자 #<hash>"`, email → null, profile_image_url → null, `deleted_at` = now. googleId 유지. | hash = SHA-256(userId)[0:3] uppercase. 비가역 + 사용자별 고유 |
| `buy_orders` (status='OPEN') | `status` → `'CANCELED'` 자동 일괄 | 다른 사용자에게 매수 호가가 dangling으로 남는 거 방지 |
| `buy_orders` (status='MATCHED') | 보존 | 거래 이력 |
| `trade_posts` (status='OPEN'/'RESERVED') | `markDeleted()` → status='DELETED' 일괄 | 활성 판매글 정리 |
| `trade_posts` (status='COMPLETED') | 보존 | 거래 이력 — 다른 사용자에게 "탈퇴한 사용자"로 표시 |
| `chat_messages` | 보존 | 분쟁 증거. sender 닉네임은 마스킹된 값 노출 |
| `chat_rooms` | 보존 | 같은 이유 |
| `reports` (신고) | **절대 보존, hard delete 금지** | 사기 누적 패턴 추적 — 사기꾼이 계정 만들고 사기 치고 탈퇴하고 반복하는 통로 차단 |
| `blocks` (차단) | 보존 | 다른 사용자가 한 차단 관계 보호 |
| `card_interests` / `post_interests` | 보존 (이번 P0-A 범위 외) | DTO에서 user nickname이 마스킹되므로 노출엔 문제 X. v1.1에서 hard delete 가능 |
| `notifications` | 보존 (P0-A 범위 외) | 동일 |
| `assets` | 보존 (P0-A 범위 외) | FK 종속이 trade_posts 등에 있음. v1.1에서 정책 결정 |

## 흐름

```
[사용자] MY → 계정 삭제 → confirm dialog
   ↓
[프론트] DELETE /api/users/me  (Authorization: Bearer JWT)
   ↓
[백엔드] UserController.deleteMyAccount(@AuthenticationPrincipal userId)
   ↓
[백엔드] UserService.deleteAccount(userId)
   1. BuyOrder OPEN → CANCELED (status update)
   2. TradePost OPEN/RESERVED → DELETED (markDeleted)
   3. User: nickname="탈퇴한 사용자 #<hash>", email=null, profile_image_url=null, deleted_at=now
   ↓
[프론트] 응답 status='success' → AuthState.markLoggedOut() + TokenStorage.delete()
   → router redirect → /login
   ↓
[이후 모든 인증 API 호출] DeletedUserGuardFilter가 deleted_at != null 감지 → 401 + USER_DELETED
```

## 보안

- **userId는 JWT subject에서만 추출** (`@AuthenticationPrincipal`). request param/body로 받지 않음.
- 다른 사용자 ID를 param으로 받아 삭제하는 IDOR 공격 불가.
- JWT가 만료 전이라도 `DeletedUserGuardFilter`가 즉시 차단.
- 동시 요청 race: `User.deletedAt != null` 체크 → 이미 탈퇴면 badRequest.

## 운영 메모

- **재가입 시도 차단**: 동일 googleId로 OAuth 콜백 시 백엔드는 `users` row 존재 + deletedAt != null 감지 → "탈퇴한 계정입니다. 새 Google 계정으로 가입하세요" 처리. (v1.1 — 현재는 신규 row 충돌(unique googleId)로 자연스럽게 차단됨, UX 메시지 정교화 필요)
- **로그**: `[UserDeletion] user=... masked_nickname=... cancelled_orders=N deleted_trades=N` info 레벨 기록.
- **모니터링**: 짧은 기간 내 다수 탈퇴 발생 시 사기 패턴 의심 → admin 알림 (v1.1).

## 마이그레이션

`back/src/main/resources/db/migration/V20260528__add_user_deleted_at.sql` 참조.
배포 흐름:
1. SSH prod → docker exec postgres → ALTER 적용
2. docker compose build back + up -d back

## 관련

- App Review Guidelines 5.1.1 (in-app account deletion)
- `back/src/main/java/com/fury/back/domain/user/UserService.java#deleteAccount`
- `back/src/main/java/com/fury/back/auth/DeletedUserGuardFilter.java`
- `front/lib/features/profile/profile_screen.dart` (MY 메뉴 진입점)
