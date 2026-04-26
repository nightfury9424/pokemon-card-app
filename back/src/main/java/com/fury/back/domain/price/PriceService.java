package com.fury.back.domain.price;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.price.dto.PriceSnapshotDto;
import com.fury.back.domain.price.dto.PriceSummaryDto;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class PriceService {

    private final PriceSnapshotRepository priceSnapshotRepository;
    private final PriceSummaryRepository priceSummaryRepository;

    public ReturnData<List<PriceSnapshotDto>> getRecentSnapshots(String cardId) {
        List<PriceSnapshotDto> result = priceSnapshotRepository
                .findByCardIdOrderByTradedAtDesc(cardId)
                .stream()
                .map(PriceSnapshotDto::from)
                .toList();
        return ReturnData.success(result);
    }

    public ReturnData<List<PriceSummaryDto>> getSummaries(String cardId) {
        List<PriceSummaryDto> result = priceSummaryRepository.findByCardId(cardId)
                .stream()
                .map(PriceSummaryDto::from)
                .toList();
        return ReturnData.success(result);
    }
}
