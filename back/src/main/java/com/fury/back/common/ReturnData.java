package com.fury.back.common;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class ReturnData<T> {
    private String status;
    private String code;
    private String message;
    private T data;

    public ReturnData(String status, String code, String message, T data) {
        this.status = status;
        this.code = code;
        this.message = message;
        this.data = data;
    }

    public static <T> ReturnData<T> success(T data) {
        return new ReturnData<>(ProcessCode.STATUS_SUCCESS, ProcessCode.CODE_SUCCESS, "성공", data);
    }

    public static <T> ReturnData<T> success() {
        return new ReturnData<>(ProcessCode.STATUS_SUCCESS, ProcessCode.CODE_SUCCESS, "성공", null);
    }

    public static <T> ReturnData<T> fail(String code, String message) {
        return new ReturnData<>(ProcessCode.STATUS_FAIL, code, message, null);
    }

    public static <T> ReturnData<T> notFound(String message) {
        return new ReturnData<>(ProcessCode.STATUS_FAIL, ProcessCode.CODE_NOT_FOUND, message, null);
    }

    public static <T> ReturnData<T> badRequest(String message) {
        return new ReturnData<>(ProcessCode.STATUS_FAIL, ProcessCode.CODE_BAD_REQUEST, message, null);
    }
}
