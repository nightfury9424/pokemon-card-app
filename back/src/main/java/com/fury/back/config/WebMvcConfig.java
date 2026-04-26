package com.fury.back.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    @Value("${card.image.dir}")
    private String cardImageDir;

    @Value("${trade.image.dir}")
    private String tradeImageDir;

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/images/cards/**")
                .addResourceLocations("file:" + cardImageDir + "/");
        registry.addResourceHandler("/images/trades/**")
                .addResourceLocations("file:" + tradeImageDir + "/");
    }
}
