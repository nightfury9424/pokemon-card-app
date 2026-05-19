package com.fury.back.domain.chat;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import com.fury.back.storage.StorageKeyUrls;
import lombok.RequiredArgsConstructor;
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

    @Override
    @Transactional
    public ChatRoomDto getOrCreateRoom(String saleListingId, String buyerUserId) {
        TradePost trade = tradePostRepository.findById(saleListingId)
                .orElseThrow(() -> new IllegalArgumentException("거래글 없음: " + saleListingId));

        ChatRoom room = chatRoomRepository
                .findBySaleListingIdAndBuyerUserId(saleListingId, buyerUserId)
                .orElseGet(() -> chatRoomRepository.save(ChatRoom.builder()
                        .chatRoomId(IdGenerator.generate())
                        .saleListingId(saleListingId)
                        .sellerUserId(trade.getSellerId())
                        .buyerUserId(buyerUserId)
                        .build()));

        User other = userRepository.findById(trade.getSellerId()).orElse(null);
        long unread = chatMessageRepository
                .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), buyerUserId);

        return ChatRoomDto.from(room, buyerUserId,
                trade.getTitle(), StorageKeyUrls.firstProxyUrl(trade.getImageUrl()),
                other != null ? other.getNickname() : "",
                other != null ? other.getProfileImageUrl() : "",
                unread);
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

        return rooms.stream().map(room -> {
            String otherUserId = userId.equals(room.getBuyerUserId())
                    ? room.getSellerUserId() : room.getBuyerUserId();
            User other = userMap.get(otherUserId);
            TradePost trade = tradeMap.get(room.getSaleListingId());
            long unread = chatMessageRepository
                    .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), userId);
            return ChatRoomDto.from(room, userId,
                    trade != null ? trade.getTitle() : "",
                    trade != null ? StorageKeyUrls.firstProxyUrl(trade.getImageUrl()) : null,
                    other != null ? other.getNickname() : "",
                    other != null ? other.getProfileImageUrl() : "",
                    unread);
        }).toList();
    }

    @Override
    @Transactional
    public List<ChatMessageDto> getMessages(String roomId, String userId) {
        chatMessageRepository.markAllAsRead(roomId, userId);

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
