package com.fury.back.common;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<ReturnData<?>> handleResponseStatus(ResponseStatusException e) {
        return ResponseEntity.status(e.getStatusCode())
                .body(ReturnData.fail(String.valueOf(e.getStatusCode().value()), e.getReason()));
    }

    @ResponseStatus(HttpStatus.OK)
    @ExceptionHandler(IllegalArgumentException.class)
    public ReturnData<?> handleIllegalArgument(IllegalArgumentException e) {
        return ReturnData.notFound(e.getMessage());
    }

    @ResponseStatus(HttpStatus.OK)
    @ExceptionHandler(Exception.class)
    public ReturnData<?> handleException(Exception e) {
        return ReturnData.fail(ProcessCode.CODE_SERVER_ERROR, "서버 오류가 발생했습니다: " + e.getMessage());
    }
}
