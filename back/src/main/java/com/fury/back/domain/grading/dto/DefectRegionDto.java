package com.fury.back.domain.grading.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class DefectRegionDto {
    private String type;
    private List<Double> bbox;
    private String side;
    private String color;
}
