package com.fury.back.domain.grading.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class DeductionReasonDto {
    private String id;
    private String type;
    private String label;
    private String side;
    private String position;
    private String severity;
    private Double confidence;
    private BigDecimal penalty;
    private List<Double> bbox;
    private String explanation;
}
