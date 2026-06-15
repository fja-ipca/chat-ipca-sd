export interface User {
  id: string; // Socket ID
  nickname: string;
}

export interface ChatRoom {
  id: string;
  name: string;
  isPrivate: boolean;
  participants: User[]; // Used mainly for private rooms if needed, but we track dynamic presence
}

export interface ChatMessage {
  id: string;
  roomId: string;
  senderId: string;
  senderNickname: string;
  content: string;
  timestamp: string;
}
