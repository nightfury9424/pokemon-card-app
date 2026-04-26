package com.fury.back.domain.grading;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "grading_results")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class GradingResult {

    @Id
    @Column(name = "result_id", length = 50)
    private String resultId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    @Column(name = "card_id", length = 50)
    private String cardId;

    @Column(name = "centering_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal centeringScore;

    @Column(name = "corner_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal cornerScore;

    @Column(name = "surface_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal surfaceScore;

    @Column(name = "whitening_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal whiteningScore;

    @Column(name = "total_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal totalScore;

    @Column(name = "heavy_whitening", nullable = false)
    private boolean heavyWhitening;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
}
