package com.fury.back.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    @Value("${card.image.dir}")
    private String cardImageDir;

    @Value("${trade.image.dir}")
    private String tradeImageDir;

    @Value("${asset.grading.image.dir:${user.home}/pokemon-card-app/asset_grading_images}")
    private String assetGradingImageDir;

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/images/cards/**")
                .addResourceLocations("file:" + cardImageDir + "/");
        registry.addResourceHandler("/images/trades/**")
                .addResourceLocations("file:" + tradeImageDir + "/");
        registry.addResourceHandler("/images/asset-grading/**")
                .addResourceLocations("file:" + assetGradingImageDir + "/");
    }

    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}
