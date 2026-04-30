package com.fury.back.domain.card;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.dto.CardDto;
import com.fury.back.domain.card.dto.CardSearchDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.*;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import java.util.List;

@Tag(name = "Card", description = "카드 마스터 조회 API")
@RestController
@RequestMapping("/api/cards")
@RequiredArgsConstructor
public class CardController {

    private final CardService cardService;

    @Operation(summary = "카드 상세 조회", description = "cardId로 카드 마스터 정보를 조회합니다.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "조회 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": {
                        "cardId": "CRD_ABC123",
                        "name": "리자몽 ex",
                        "rarityCode": "SAR",
                        "imageUrl": "https://cards.image.pokemonkorea.co.kr/...",
                        "superType": "POKEMON"
                      }
                    }""")))
    })
    @GetMapping("/{cardId}")
    public ReturnData<CardDto> getCard(
        @Parameter(description = "카드 ID", example = "CRD_ABC123")
        @PathVariable String cardId) {
        return cardService.getCard(cardId);
    }

    @Operation(summary = "고레어 카드 목록 조회", description = "레어도별 카드 목록 조회 (시세 화면용). rarities 미입력시 SAR,SSR,CSR,SR,UR,CHR 기본값. sortBy=price 로 가격순 정렬 가능.")
    @GetMapping("/market")
    public ReturnData<Map<String, Object>> getMarketCards(
            @RequestParam(defaultValue = "SAR,SSR,CSR,SR,UR,CHR") String rarities,
            @RequestParam(defaultValue = "") String name,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "") String sortBy) {
        List<String> rarityList = Arrays.asList(rarities.split(","));
        if ("price".equals(sortBy)) {
            var result = cardService.getCardsByRarityOrderByPrice(rarityList, name, size, page * size);
            return ReturnData.success(result);
        }
        var pageable = PageRequest.of(page, size);
        var result = name.isBlank()
                ? cardService.getCardsByRarity(rarityList, pageable)
                : cardService.searchCardsByNameAndRarity(name, rarityList, pageable);
        return ReturnData.success(result);
    }

    @Operation(summary = "카드명 검색", description = "카드명으로 카드를 검색합니다. (부분 일치)")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "검색 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": [
                        { "cardId": "CRD_ABC123", "name": "리자몽 ex", "rarityCode": "SAR" }
                      ]
                    }""")))
    })
    @GetMapping("/search")
    public ReturnData<List<CardSearchDto>> searchCards(
        @Parameter(description = "카드명 (부분 일치)", example = "리자몽")
        @RequestParam String name) {
        return cardService.searchCards(name);
    }

    @Operation(summary = "공식 카드 코드 조회", description = "공식 카드 코드(예: BS2022016088)로 카드를 조회합니다.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "조회 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": {
                        "cardId": "CRD_ABC123",
                        "officialCardCode": "BS2022016088",
                        "name": "리자몽 ex"
                      }
                    }""")))
    })
    @GetMapping("/code/{officialCardCode}")
    public ReturnData<CardDto> getCardByCode(
        @Parameter(description = "공식 카드 코드", example = "BS2022016088")
        @PathVariable String officialCardCode) {
        return cardService.getCardByCode(officialCardCode);
    }

    @Operation(summary = "팩(상품)별 카드 목록 조회", description = "productId로 해당 팩에 수록된 카드를 모두 조회합니다.")
    @GetMapping("/product/{productId}")
    public ReturnData<List<CardDto>> getCardsByProduct(
            @PathVariable String productId) {
        return cardService.getCardsByProduct(productId);
    }

    @Operation(summary = "수록번호로 카드 조회", description = "OCR 스캐너에서 인식한 수록번호(예: 023/198)로 카드를 조회합니다.")
    @GetMapping("/number/{collectionNumber}")
    public ReturnData<List<CardDto>> getCardsByNumber(
        @PathVariable String collectionNumber,
        @RequestParam(defaultValue = "KO") String language) {
        return cardService.getCardsByCollectionNumber(collectionNumber, language);
    }

    @Operation(summary = "스캔 결과 카드 조회", description = """
        Python 스캐너에서 카드를 인식한 뒤 호출하는 API입니다.
        officialCardCode로 DB에서 카드를 조회하고 카드 정보를 반환합니다.
        """)
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "스캔 결과 조회 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": {
                        "cardId": "CRD_ABC123",
                        "officialCardCode": "BS2022016088",
                        "name": "리자몽 ex",
                        "rarityCode": "SAR",
                        "imageUrl": "https://cards.image.pokemonkorea.co.kr/...",
                        "superType": "POKEMON"
                      }
                    }""")))
    })
    @PostMapping("/scan")
    public ReturnData<CardDto> registerScanResult(
        @RequestBody
        @io.swagger.v3.oas.annotations.parameters.RequestBody(
            description = "스캔 결과 카드 조회 요청",
            content = @Content(examples = @ExampleObject(value = """
                { "data": { "officialCardCode": "BS2022016088" } }""")))
        ParameterData parameterData) {
        return cardService.registerScanResult(parameterData);
    }
}
