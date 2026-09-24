/**
 * ChatMessage Model - erweiterbar
 */
export interface ChatMessage {
  id: string;
  role: 'user' | 'ai' | 'system';
  text: string;
  thinking?: string;
  timestamp: number;
  truncated?: boolean;
  type?: MessageType;
  meta?: Record<string, string>;
}

export enum MessageType {
  CHAT = 'chat',
  WEATHER = 'weather',
  TRANSLATE = 'translate',
  SUMMARY = 'summary',
  SYSTEM = 'system'
}

export interface BridgePayload {
  id: string;
  prompt?: string;
  response?: string;
  thinking?: string;
  error?: string;
  type?: string;
  target_lang?: string;
  chunk_index?: number;
  chunk_total?: number;
  chunk_data?: string;
  is_chunked?: boolean;
  truncated?: boolean;
  took_ms?: number;
}

export interface AppConfig {
  androidPackage: string;
  androidFingerprint: string;
  maxHistory: number;
  maxInputLen: number;
  timeoutMs: number;
}
