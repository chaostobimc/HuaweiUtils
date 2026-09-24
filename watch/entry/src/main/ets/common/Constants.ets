/**
 * Constants - zentral, erweiterbar
 */
import { AppConfig } from '../models/ChatMessage';

export class Constants {
  static readonly TAG = 'AI-Watch-GT6';
  static readonly ANDROID_PACKAGE = 'com.huawei.ai.bridge';
  static readonly ANDROID_FINGERPRINT = 'YOUR_ANDROID_FINGERPRINT_WITHOUT_COLONS'; // replace with real SHA256
  static readonly MAX_HISTORY = 15;
  static readonly MAX_INPUT = 500;
  static readonly REQUEST_TIMEOUT_MS = 35000;
  static readonly CHUNK_SIZE = 800;

  static readonly DEFAULT_CONFIG: AppConfig = {
    androidPackage: Constants.ANDROID_PACKAGE,
    androidFingerprint: Constants.ANDROID_FINGERPRINT,
    maxHistory: Constants.MAX_HISTORY,
    maxInputLen: Constants.MAX_INPUT,
    timeoutMs: Constants.REQUEST_TIMEOUT_MS
  };

  // Quick actions für erweiterte Features
  static readonly QUICK_ACTIONS = [
    { label: 'Zusammenfassen', prompt: 'Fasse zusammen: ', type: 'summarize' },
    { label: 'Übersetzen EN', prompt: 'Übersetze nach Englisch: ', type: 'translate', lang: 'en' },
    { label: 'Erkläre', prompt: 'Erkläre einfach: ', type: 'chat' },
  ];
}

export enum FeatureFlag {
  THINKING = 'thinking',
  SEARCH = 'search',
  CHUNKING = 'chunking'
}
