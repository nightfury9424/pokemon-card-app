package com.fury.back.common;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

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
