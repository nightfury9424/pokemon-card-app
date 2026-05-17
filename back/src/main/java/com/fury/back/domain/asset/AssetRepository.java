package com.fury.back.domain.asset;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AssetRepository extends JpaRepository<Asset, String> {
    List<Asset> findByUserId(String userId);

    List<Asset> findByUserIdAndCardId(String userId, String cardId);

    /** 카드별 보유자 list (알림 대상 추출용) */
    List<Asset> findByCardId(String cardId);
}
