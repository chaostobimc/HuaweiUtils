/**
 * AiService - Business Logik, unabhängig von WearEngine
 * Macht App erweiterbar: hier neue Features hinzufügen
 */
import { ChatMessage, MessageType, BridgePayload } from '../models/ChatMessage';
import { Constants } from '../common/Constants';

export class AiService {
  // Erstellt Payload für verschiedene Typen
  static createChatPayload(prompt: string, id: string, type: MessageType = MessageType.CHAT, extra?: Record<string, string>): BridgePayload {
    const trimmed = prompt.length > Constants.MAX_INPUT ? prompt.slice(0, Constants.MAX_INPUT) : prompt;
    return {
      id,
      prompt: trimmed,
      type: type.toString(),
      ...extra
    };
  }

  static createSummarizePayload(text: string, id: string): BridgePayload {
    return this.createChatPayload(`Fasse kurz zusammen (max 3 Sätze): ${text}`, id, MessageType.SUMMARY);
  }

  static createTranslatePayload(text: string, targetLang: string, id: string): BridgePayload {
    return this.createChatPayload(text, id, MessageType.TRANSLATE, { target_lang: targetLang });
  }

  static createWeatherPayload(location: string, id: string): BridgePayload {
    return this.createChatPayload(`Wetter in ${location} heute kurz`, id, MessageType.WEATHER);
  }

  // Parst Antwort vom Pi
  static parseResponse(jsonStr: string): ChatMessage | null {
    try {
      const payload = JSON.parse(jsonStr) as BridgePayload;
      if (payload.is_chunked) return null; // handled elsewhere

      if (payload.error) {
        return {
          id: payload.id || Date.now().toString(),
          role: 'system',
          text: `Fehler: ${payload.error} ${payload.response || ''}`.trim(),
          timestamp: Date.now(),
          type: MessageType.SYSTEM
        };
      }

      if (payload.response) {
        return {
          id: payload.id || Date.now().toString(),
          role: 'ai',
          text: payload.response,
          thinking: payload.thinking,
          timestamp: Date.now(),
          truncated: payload.truncated,
          type: (payload.type as MessageType) || MessageType.CHAT
        };
      }
      return null;
    } catch (e) {
      // Fallback plain text
      return {
        id: Date.now().toString(),
        role: 'ai',
        text: jsonStr.slice(0, 800),
        timestamp: Date.now(),
        type: MessageType.CHAT
      };
    }
  }

  // Quick prompt helpers
  static getQuickPrompts(): Array<{label: string, prompt: string, type: MessageType}> {
    return [
      { label: '💡 Erkläre', prompt: 'Erkläre einfach: ', type: MessageType.CHAT },
      { label: '📝 Zusammenfassen', prompt: '', type: MessageType.SUMMARY },
      { label: '🌐 EN', prompt: '', type: MessageType.TRANSLATE },
      { label: '☀️ Wetter', prompt: '', type: MessageType.WEATHER }
    ];
  }
}
