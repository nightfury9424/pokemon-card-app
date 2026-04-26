package com.fury.back.common;

import lombok.Getter;
import lombok.Setter;

import java.util.Map;

@Getter
@Setter
public class ParameterData {
    private Map<String, Object> data;

    public String getString(String key) {
        Object val = data == null ? null : data.get(key);
        return val == null ? null : String.valueOf(val);
    }

    public Integer getInteger(String key) {
        Object val = data == null ? null : data.get(key);
        if (val == null) return null;
        if (val instanceof Integer i) return i;
        try { return Integer.parseInt(String.valueOf(val)); } catch (Exception e) { return null; }
    }

    public Boolean getBoolean(String key) {
        Object val = data == null ? null : data.get(key);
        if (val == null) return null;
        if (val instanceof Boolean b) return b;
        return Boolean.parseBoolean(String.valueOf(val));
    }
}
