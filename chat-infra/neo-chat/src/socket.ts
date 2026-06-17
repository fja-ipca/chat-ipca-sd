import { io } from 'socket.io-client';

// Use standard path or URL. Since Express hosts Vite, relative path works.
// Note: io() connects to the same host by default.
// Force websocket to avoid issues with polling/multiple instances
export const socket: Socket = io({
  transports: ['websocket'],
});
