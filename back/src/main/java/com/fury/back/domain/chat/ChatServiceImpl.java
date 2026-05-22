package com.fury.back.domain.chat;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;
import com.fury.back.domain.chat.event.ChatReadEvent;
import com.fury.back.domain.chat.event.SystemMessageEvent;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import com.fury.back.storage.CardCdnUrls;
import com.fury.back.storage.StorageKeyUrls;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ChatServiceImpl implements ChatService {

    private final ChatRoomRepository chatRoomRepository;
    private final ChatMessageRepository chatMessageRepository;
    private final TradePostRepository tradePostRepository;
    private final UserRepository userRepository;
    private final ApplicationEventPublisher eventPublisher;
    // Bundle 2-A: 거래 미니카드용 카드 마스터 이미지 조립 (#62 CardCdnUrls 재활용).
    private final CardRepository cardRepository;
    private final CardCdnUrls cardCdnUrls;

    @Override
    @Transactional
    public ChatRoomDto getOrCreateRoom(String saleListingId, String buyerUserId) {
        TradePost trade = tradePostRepository.findById(saleListingId)
                .orElseThrow(() -> new IllegalArgumentException("거래글 없음: " + saleListingId));

        // Bundle 2-A.2: (saleListingId, buyerUserId) 1:1 unique 채팅방 정책.
        // DB UNIQUE 인덱스(uq_chat_rooms_sale_buyer) + race-safe 가드 — 동시 요청 시
        // 첫 lookup empty 두 번째도 empty라 둘 다 save 시도해도 DB UNIQUE violation으로
        // 두 번째가 fail → catch 후 다시 findBy* 호출하면 첫 번째 row 반환.
        //
        // Bundle 2-A.6: 신규 채팅방 생성은 OPEN 거래만 허용 (비즈니스 룰).
        // 기존 채팅방은 status 무관 반환 — 이미 대화 중인 buyer는 진행/배송/분쟁 대화 계속 필요.
        // 프론트 CTA disabled와 별개로 백엔드도 가드 (악의 API 직접 호출 차단).
        ChatRoom room = chatRoomRepository
                .findBySaleListingIdAndBuyerUserId(saleListingId, buyerUserId)
                .orElseGet(() -> {
                    if (!"OPEN".equals(trade.getStatus())) {
                        throw new IllegalStateException(switch (trade.getStatus()) {
                            case "RESERVED" -> "예약 중인 거래입니다.";
                            case "COMPLETED" -> "거래가 완료되었습니다.";
                            case "CANCELED" -> "취소된 거래입니다.";
                            case "DELETED" -> "삭제된 거래입니다.";
                            default -> "현재 거래 상태에서는 채팅을 시작할 수 없습니다.";
                        });
                    }
                    try {
                        return chatRoomRepository.saveAndFlush(ChatRoom.builder()
                                .chatRoomId(IdGenerator.generate())
                                .saleListingId(saleListingId)
                                .sellerUserId(trade.getSellerId())
                                .buyerUserId(buyerUserId)
                                .build());
                    } catch (org.springframework.dao.DataIntegrityViolationException e) {
                        // 동시 요청 race — 다른 요청이 먼저 생성. 그 row를 가져옴.
                        return chatRoomRepository
                                .findBySaleListingIdAndBuyerUserId(saleListingId, buyerUserId)
                                .orElseThrow(() -> e);
                    }
                });

        User other = userRepository.findById(trade.getSellerId()).orElse(null);
        long unread = chatMessageRepository
                .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), buyerUserId);

        // Bundle 2-A: 카드 마스터 이미지 조립. card 매칭 부재 시 null (프론트 placeholder).
        Card card = trade.getCardId() != null
                ? cardRepository.findById(trade.getCardId()).orElse(null)
                : null;
        String cardImageUrl = card != null ? cardCdnUrls.forCard(card) : null;

        return ChatRoomDto.from(room, buyerUserId,
                trade.getTitle(), StorageKeyUrls.firstProxyUrl(trade.getImageUrl()),
                other != null ? other.getNickname() : "",
                other != null ? other.getProfileImageUrl() : "",
                unread,
                trade.getStatus(), trade.getPrice(), cardImageUrl);
    }

    @Override
    public List<ChatRoomDto> getMyRooms(String userId) {
        List<ChatRoom> rooms = chatRoomRepository.findMyRooms(userId);

        // 필요한 userId 수집
        List<String> userIds = rooms.stream()
                .flatMap(r -> java.util.stream.Stream.of(r.getBuyerUserId(), r.getSellerUserId()))
                .distinct().toList();
        Map<String, User> userMap = userRepository.findAllById(userIds).stream()
                .collect(Collectors.toMap(User::getUserId, u -> u));

        List<String> tradeIds = rooms.stream().map(ChatRoom::getSaleListingId).distinct().toList();
        Map<String, TradePost> tradeMap = tradePostRepository.findAllById(tradeIds).stream()
                .collect(Collectors.toMap(TradePost::getTradeId, t -> t));

        // Bundle 2-A: 카드 마스터 이미지 batch 조회 (N+1 차단). null cardId/empty skip.
        List<String> cardIds = tradeMap.values().stream()
                .map(TradePost::getCardId)
                .filter(id -> id != null && !id.isBlank())
                .distinct().toList();
        Map<String, Card> cardMap = cardIds.isEmpty()
                ? Map.of()
                : cardRepository.findAllById(cardIds).stream()
                        .collect(Collectors.toMap(Card::getCardId, c -> c));

        return rooms.stream().map(room -> {
            String otherUserId = userId.equals(room.getBuyerUserId())
                    ? room.getSellerUserId() : room.getBuyerUserId();
            User other = userMap.get(otherUserId);
            TradePost trade = tradeMap.get(room.getSaleListingId());
            Card card = (trade != null && trade.getCardId() != null)
                    ? cardMap.get(trade.getCardId())
                    : null;
            String cardImageUrl = card != null ? cardCdnUrls.forCard(card) : null;
            long unread = chatMessageRepository
                    .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), userId);
            return ChatRoomDto.from(room, userId,
                    trade != null ? trade.getTitle() : "",
                    trade != null ? StorageKeyUrls.firstProxyUrl(trade.getImageUrl()) : null,
                    other != null ? other.getNickname() : "",
                    other != null ? other.getProfileImageUrl() : "",
                    unread,
                    trade != null ? trade.getStatus() : null,
                    trade != null ? trade.getPrice() : null,
                    cardImageUrl);
        }).toList();
    }

    @Override
    @Transactional
    public List<ChatMessageDto> getMessages(String roomId, String userId) {
        // Bundle 1 G1: 실제 read 갱신된 행이 있을 때만 read 이벤트 발행.
        // 이벤트는 @TransactionalEventListener(AFTER_COMMIT)로 STOMP broadcast → sender 화면 "1" 사라짐.
        int updated = chatMessageRepository.markAllAsRead(roomId, userId);
        if (updated > 0) {
            eventPublisher.publishEvent(new ChatReadEvent(roomId, userId));
        }

        Map<String, User> userMap = userRepository.findAllById(
                chatMessageRepository.findByChatRoomIdOrderByCreatedAtAsc(roomId)
                        .stream().map(ChatMessage::getSenderUserId).distinct().toList()
        ).stream().collect(Collectors.toMap(User::getUserId, u -> u));

        return chatMessageRepository.findByChatRoomIdOrderByCreatedAtAsc(roomId)
                .stream().map(msg -> {
                    User sender = userMap.get(msg.getSenderUserId());
                    return ChatMessageDto.from(msg,
                            sender != null ? sender.getNickname() : "",
                            sender != null ? sender.getProfileImageUrl() : "");
                }).toList();
    }

    /**
     * Bundle 1.5: chat_room active 상태에서 새 메시지 STOMP 수신 시 호출.
     * - 권한 체크 (room 참여자만)
     * - markAllAsRead 후 affected > 0이면 ChatReadEvent → AFTER_COMMIT broadcast
     * - 메시지 리스트 반환 X (lightweight)
     */
    @Override
    @Transactional
    public void markRoomAsRead(String roomId, String userId) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        if (!userId.equals(room.getBuyerUserId()) && !userId.equals(room.getSellerUserId())) {
            throw new IllegalArgumentException("채팅방 참여자가 아닙니다.");
        }
        int updated = chatMessageRepository.markAllAsRead(roomId, userId);
        if (updated > 0) {
            eventPublisher.publishEvent(new ChatReadEvent(roomId, userId));
        }
    }

    /**
     * Bundle 2-C: 시스템 메시지 전송. sender_user_id='SYSTEM' + message_type='SYSTEM' 저장.
     * - last_message 갱신 (Codex 권장 (c) — 시간순 일관성, chat_screen 분기는 별도 polish)
     * - SystemMessageEvent publish → AFTER_COMMIT 리스너가 STOMP broadcast
     *   (commit 실패 시 메시지만 먼저 퍼지는 race 차단)
     */
    @Override
    @Transactional
    public ChatMessageDto sendSystemMessage(String roomId, String content) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));

        ChatMessage saved = chatMessageRepository.save(ChatMessage.builder()
                .chatMessageId(IdGenerator.generate())
                .chatRoomId(roomId)
                .senderUserId("SYSTEM")
                .message(content)
                .messageType("SYSTEM")
                .build());

        room.updateLastMessage(content);
        chatRoomRepository.save(room);

        // SYSTEM은 user lookup skip — ChatMessageDto.from 내부에서 nickname="시스템" 고정.
        ChatMessageDto dto = ChatMessageDto.from(saved, null, null);
        eventPublisher.publishEvent(new SystemMessageEvent(roomId, dto));
        return dto;
    }

    @Override
    @Transactional
    public ChatMessageDto sendMessage(String roomId, String senderUserId, String message) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));

        ChatMessage saved = chatMessageRepository.save(ChatMessage.builder()
                .chatMessageId(IdGenerator.generate())
                .chatRoomId(roomId)
                .senderUserId(senderUserId)
                .message(message)
                .build());

        room.updateLastMessage(message);
        chatRoomRepository.save(room);

        User sender = userRepository.findById(senderUserId).orElse(null);
        return ChatMessageDto.from(saved,
                sender != null ? sender.getNickname() : "",
                sender != null ? sender.getProfileImageUrl() : "");
    }
}
