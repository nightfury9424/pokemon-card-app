package com.fury.back.auth;

import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jws;
import io.jsonwebtoken.Jwts;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.math.BigInteger;
import java.security.KeyFactory;
import java.security.Key;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Sign in with Apple — iOS native identity token 검증 후 로그인.
 *  - Apple 공개키(JWK)로 RS256 서명 검증 + iss/aud/exp 검증.
 *  - sub(고유 Apple id) → apple_id 로 사용자 생성/조회.
 */
@Service
@RequiredArgsConstructor
public class AppleAuthService {

    private static final String APPLE_ISS = "https://appleid.apple.com";
    private static final String APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";

    private final UserRepository userRepository;
    private final JwtUtil jwtUtil;
    private final RestClient restClient = RestClient.create();

    /** iOS 앱 bundle id (identity token 의 aud). */
    @Value("${apple.bundle-id:com.fury.pokemoncardapp}")
    private String appleBundleId;

    public GoogleAuthService.LoginResult loginWithIdToken(String identityToken) {
        Claims claims = verify(identityToken);

        String appleId = claims.getSubject();
        if (appleId == null || appleId.isBlank()) {
            throw new IllegalArgumentException("Apple 토큰에 sub 가 없습니다.");
        }
        String email = claims.get("email", String.class);

        User user = userRepository.findByAppleId(appleId)
                .map(existing -> {
                    // 2026-06-08: 탈퇴(deletedAt) 계정 재로그인 차단 — App Store 5.1.1 / PIPA. soft-delete row 는 3개월 보존.
                    if (existing.getDeletedAt() != null) {
                        // 403 — IllegalArgumentException(=200+notFound)은 앱이 성공 오인 위험이라 명시적 status.
                        throw new org.springframework.web.server.ResponseStatusException(
                                org.springframework.http.HttpStatus.FORBIDDEN,
                                "탈퇴한 계정입니다. 탈퇴 후에는 다시 로그인할 수 없어요.");
                    }
                    return existing;
                })
                .orElseGet(() -> createUser(appleId, email));

        return new GoogleAuthService.LoginResult(jwtUtil.generate(user.getUserId()), user.isOnboarded());
    }

    /** identity token 서명/클레임 검증 후 Claims 반환. 실패 시 예외. */
    private Claims verify(String identityToken) {
        Jws<Claims> jws = Jwts.parser()
                .keyLocator(header -> resolveApplePublicKey((String) header.get("kid")))
                .requireIssuer(APPLE_ISS)
                .requireAudience(appleBundleId)
                .build()
                .parseSignedClaims(identityToken);
        return jws.getPayload();
    }

    /** kid 에 해당하는 Apple 공개키(JWK)를 RSAPublicKey 로 변환. */
    private Key resolveApplePublicKey(String kid) {
        if (kid == null) throw new IllegalArgumentException("Apple 토큰 헤더에 kid 가 없습니다.");
        Map<String, Object> jwkSet = restClient.get()
                .uri(APPLE_KEYS_URL)
                .retrieve()
                .body(new ParameterizedTypeReference<>() {});
        @SuppressWarnings("unchecked")
        List<Map<String, String>> keys = (List<Map<String, String>>) (jwkSet != null ? jwkSet.get("keys") : null);
        if (keys == null) throw new IllegalStateException("Apple JWK 조회 실패");
        for (Map<String, String> k : keys) {
            if (kid.equals(k.get("kid"))) {
                return buildRsaPublicKey(k.get("n"), k.get("e"));
            }
        }
        throw new IllegalArgumentException("Apple 공개키(kid=" + kid + ")를 찾을 수 없습니다.");
    }

    private RSAPublicKey buildRsaPublicKey(String n, String e) {
        try {
            BigInteger modulus = new BigInteger(1, Base64.getUrlDecoder().decode(n));
            BigInteger exponent = new BigInteger(1, Base64.getUrlDecoder().decode(e));
            return (RSAPublicKey) KeyFactory.getInstance("RSA")
                    .generatePublic(new RSAPublicKeySpec(modulus, exponent));
        } catch (Exception ex) {
            throw new IllegalStateException("Apple 공개키 파싱 실패", ex);
        }
    }

    private User createUser(String appleId, String email) {
        User user = User.builder()
                .userId("USR_" + UUID.randomUUID().toString().replace("-", "").substring(0, 20).toUpperCase())
                .appleId(appleId)
                .email(email != null ? email : "")
                .onboarded(false)
                .build();
        return userRepository.save(user);
    }
}
