package com.fury.back.storage;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3ClientBuilder;

import java.net.URI;

/**
 * Phase 1-7: S3Client Bean — app.image-storage.type=s3일 때만 활성.
 *
 * - aws.s3.endpoint가 비어있으면 AWS S3 default endpoint 사용 (Seoul region).
 * - aws.s3.endpoint=http://localhost:9000 등 명시 시 MinIO/R2 등 S3-compatible 호환.
 * - credentials는 IAM user access key/secret (Lightsail은 IAM role 미지원).
 */
@Slf4j
@Configuration
@ConditionalOnProperty(name = "app.image-storage.type", havingValue = "s3")
public class S3Config {

    @Bean
    public S3Client s3Client(
            @Value("${aws.s3.region}") String region,
            @Value("${aws.s3.endpoint:}") String endpoint,
            @Value("${aws.access-key}") String accessKey,
            @Value("${aws.secret-key}") String secretKey
    ) {
        if (accessKey == null || accessKey.isBlank()
                || secretKey == null || secretKey.isBlank()) {
            throw new IllegalStateException(
                    "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set when app.image-storage.type=s3.");
        }

        S3ClientBuilder builder = S3Client.builder()
                .region(Region.of(region))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(accessKey, secretKey)));

        if (endpoint != null && !endpoint.isBlank()) {
            // MinIO/R2 등 S3-compatible — path-style URL 강제 필요
            builder.endpointOverride(URI.create(endpoint)).forcePathStyle(true);
            log.info("[S3Config] custom endpoint={} region={} (path-style)", endpoint, region);
        } else {
            log.info("[S3Config] AWS S3 region={}", region);
        }

        return builder.build();
    }
}
