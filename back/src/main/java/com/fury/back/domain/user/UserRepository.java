package com.fury.back.domain.user;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface UserRepository extends JpaRepository<User, String> {
    Optional<User> findByGoogleId(String googleId);

    @Query("SELECT COUNT(u) > 0 FROM User u WHERE LOWER(u.nickname) = LOWER(:nickname)")
    boolean existsByNicknameIgnoreCase(@Param("nickname") String nickname);
}
