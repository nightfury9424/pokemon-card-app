package com.fury.back.domain.grading.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

@Data
public class PrecheckResultDto {
    @JsonProperty("ok")             private boolean ok;
    @JsonProperty("side")           private String side;
    @JsonProperty("quality")        private String quality;
    @JsonProperty("reason_code")    private String reasonCode;
    @JsonProperty("reason_title")   private String reasonTitle;
    @JsonProperty("reason_message") private String reasonMessage;
    @JsonProperty("blur_score")     private Double blurScore;
    @JsonProperty("glare_score")    private Double glareScore;
    @JsonProperty("exposure_score") private Double exposureScore;
    @JsonProperty("roi_score")      private Double roiScore;
}
