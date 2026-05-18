package com.fury.back.domain.price.sync;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.task.TaskExecutor;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.time.Clock;

@Configuration
@EnableAsync
public class SyncCatchUpConfig {

    @Bean
    public Clock systemClock() {
        return Clock.systemDefaultZone();
    }

    /**
     * STARTUP catch-up 전용 TaskExecutor.
     * ApplicationReadyEvent 리스너를 @Async로 실행해 30분 Python이 readiness를 차단하지 않게 한다.
     */
    @Bean(name = "syncCatchUpExecutor")
    public TaskExecutor syncCatchUpExecutor() {
        ThreadPoolTaskExecutor ex = new ThreadPoolTaskExecutor();
        ex.setCorePoolSize(1);
        ex.setMaxPoolSize(2);
        ex.setQueueCapacity(10);
        ex.setThreadNamePrefix("sync-catchup-");
        ex.initialize();
        return ex;
    }
}
