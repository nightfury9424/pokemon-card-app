package com.fury.back.common.moderation;

import com.fury.back.common.GlobalExceptionHandler;
import org.junit.jupiter.api.Test;
import org.springframework.context.support.GenericApplicationContext;
import org.springframework.web.method.ControllerAdviceBean;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Gate 1: 실제 ApplicationContext 에서 advice 우선순위가 결정적인지 검증(standalone 등록순서 무관).
 * ModerationExceptionHandler(@Order HIGHEST_PRECEDENCE)가 GlobalExceptionHandler
 * (@ExceptionHandler(Exception.class) catch-all = HTTP 200) 보다 먼저 소비돼야
 * ContentPolicyViolationException 이 200 으로 삼켜지지 않는다.
 */
class ModerationAdviceOrderTest {

    @Test
    void moderation_advice_ordered_before_global_in_real_context() {
        GenericApplicationContext ctx = new GenericApplicationContext();
        ctx.registerBean(GlobalExceptionHandler.class);
        ctx.registerBean(ModerationExceptionHandler.class);
        ctx.refresh();

        // findAnnotatedBeans 는 OrderComparator 로 정렬된 리스트를 반환 → 인덱스가 곧 소비 우선순위.
        List<ControllerAdviceBean> beans = ControllerAdviceBean.findAnnotatedBeans(ctx);
        int moderationIdx = indexOf(beans, ModerationExceptionHandler.class);
        int globalIdx = indexOf(beans, GlobalExceptionHandler.class);

        assertThat(moderationIdx).as("moderation advice 존재").isGreaterThanOrEqualTo(0);
        assertThat(globalIdx).as("global advice 존재").isGreaterThanOrEqualTo(0);
        assertThat(moderationIdx).as("moderation 이 global 보다 먼저 소비됨").isLessThan(globalIdx);

        ctx.close();
    }

    private static int indexOf(List<ControllerAdviceBean> beans, Class<?> type) {
        for (int i = 0; i < beans.size(); i++) {
            if (type.equals(beans.get(i).getBeanType())) return i;
        }
        return -1;
    }
}
