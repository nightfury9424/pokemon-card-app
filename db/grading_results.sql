CREATE TABLE grading_results (
    result_id       VARCHAR(50)    PRIMARY KEY,
    user_id         VARCHAR(50)    NOT NULL,
    card_id         VARCHAR(50),
    centering_score NUMERIC(3,1)   NOT NULL,
    corner_score    NUMERIC(3,1)   NOT NULL,
    surface_score   NUMERIC(3,1)   NOT NULL,
    whitening_score NUMERIC(3,1)   NOT NULL,
    total_score     NUMERIC(3,1)   NOT NULL,
    heavy_whitening BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP      NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_grading_results_user_id ON grading_results(user_id);
