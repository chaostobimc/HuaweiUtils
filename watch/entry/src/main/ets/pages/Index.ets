/**
 * Huawei Watch GT 6 - Private AI Assistent - Vollständig implementiert
 * Features: Chat, Summarize, Translate, Weather, Quick Actions, Settings
 * Battery Optimized, Erweiterbar
 */

import { wearEngine } from '@kit.WearEngine';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { Constants } from '../common/Constants';
import { ChatMessage, MessageType, BridgePayload } from '../models/ChatMessage';
import { AiService } from '../services/AiService';
import { WearEngineService } from '../services/WearEngineService';
import router from '@ohos.router';

@Entry
@Component
struct Index {
  // UI State
  @State inputText: string = '';
  @State messages: ChatMessage[] = [];
  @State isLoading: boolean = false;
  @State statusText: string = 'Initialisiere...';
  @State showQuickActions: boolean = false;
  @State currentType: MessageType = MessageType.CHAT;
  @State showThinking: boolean = false;

  // WearEngine
  private wearService: WearEngineService | null = null;
  private textEncoder: util.TextEncoder = new util.TextEncoder();
  private textDecoder: util.TextDecoder = new util.TextDecoder();
  private prefs: preferences.Preferences | null = null;

  // Timeout handler
  private timeoutId: number = -1;

  async aboutToAppear() {
    console.info(`[${Constants.TAG}] aboutToAppear`);
    await this.loadHistory();
    await this.initWearEngine();
  }

  aboutToDisappear() {
    console.info(`[${Constants.TAG}] aboutToDisappear`);
    if (this.timeoutId !== -1) {
      clearTimeout(this.timeoutId);
    }
    this.saveHistory();
  }

  private async loadHistory() {
    try {
      this.prefs = await preferences.getPreferences(getContext(this), 'ai_chat');
      const saved = await this.prefs.get('history', '[]') as string;
      if (saved && saved !== '[]') {
        this.messages = JSON.parse(saved) as ChatMessage[];
      } else {
        this.messages = [{
          id: 'welcome',
          role: 'system',
          text: '👋 Hallo! Ich bin dein privater AI Assistent auf GT6. Tippe eine Frage.',
          timestamp: Date.now(),
          type: MessageType.SYSTEM
        }];
      }
      const thinkingPref = await this.prefs.get('showThinking', false) as boolean;
      this.showThinking = thinkingPref;
    } catch (e) {
      console.error(`[${Constants.TAG}] loadHistory failed ${JSON.stringify(e)}`);
      this.messages = [{
        id: 'welcome',
        role: 'system',
        text: 'Hallo! Tippe eine Frage.',
        timestamp: Date.now(),
        type: MessageType.SYSTEM
      }];
    }
  }

  private async saveHistory() {
    try {
      if (this.prefs) {
        const toSave = this.messages.slice(-Constants.MAX_HISTORY);
        await this.prefs.put('history', JSON.stringify(toSave));
        await this.prefs.flush();
      }
    } catch (e) {
      console.error(`[${Constants.TAG}] saveHistory failed`);
    }
  }

  private async initWearEngine() {
    try {
      this.statusText = 'Suche Handy...';
      const context = this.getUIContext().getHostContext();
      this.wearService = new WearEngineService({
        androidPackage: Constants.ANDROID_PACKAGE,
        androidFingerprint: Constants.ANDROID_FINGERPRINT
      });

      const deviceId = await this.wearService.init(context);
      this.statusText = 'Verbunden';

      await this.wearService.registerReceiver((data: string) => {
        this.handleIncomingMessage(data);
      });

      this.statusText = 'Bereit';
      console.info(`[${Constants.TAG}] WearEngine ready deviceId=${deviceId}`);
    } catch (err) {
      const e = err as BusinessError;
      console.error(`[${Constants.TAG}] initWearEngine failed ${e.code} ${e.message}`);
      this.statusText = `Fehler ${e.code}`;
      this.messages.push({
        id: Date.now().toString(),
        role: 'system',
        text: `Verbindung fehlgeschlagen: ${e.message}. Huawei Health + Fingerprints prüfen!`,
        timestamp: Date.now(),
        type: MessageType.SYSTEM
      });
    }
  }

  private handleIncomingMessage(jsonStr: string) {
    console.info(`[${Constants.TAG}] handleIncoming len=${jsonStr.length}`);
    if (this.timeoutId !== -1) {
      clearTimeout(this.timeoutId);
      this.timeoutId = -1;
    }
    this.isLoading = false;

    const msg = AiService.parseResponse(jsonStr);
    if (msg) {
      this.messages.push(msg);
      if (this.messages.length > Constants.MAX_HISTORY) {
        this.messages = this.messages.slice(-Constants.MAX_HISTORY);
      }
      this.saveHistory();
      this.statusText = 'Bereit';
    }
  }

  private async sendPrompt(customPrompt?: string, type: MessageType = MessageType.CHAT) {
    let prompt = customPrompt !== undefined ? customPrompt : this.inputText.trim();
    if (!prompt || this.isLoading) return;
    if (!this.wearService) {
      this.statusText = 'Nicht verbunden';
      return;
    }

    const msgId = Date.now().toString();
    const payload = AiService.createChatPayload(prompt, msgId, type);

    // Für Translate/Summarize etc: wenn input leer, nimm letzte AI Nachricht
    if (type !== MessageType.CHAT && !customPrompt) {
      const lastAi = [...this.messages].reverse().find(m => m.role === 'ai');
      if (lastAi) {
        if (type === MessageType.SUMMARY) {
          const p = AiService.createSummarizePayload(lastAi.text, msgId);
          this.messages.push({ id: msgId, role: 'user', text: `📝 Zusammenfassen: "${lastAi.text.slice(0, 60)}..."`, timestamp: Date.now(), type });
          await this.sendPayload(p, msgId);
          return;
        } else if (type === MessageType.TRANSLATE) {
          const p = AiService.createTranslatePayload(lastAi.text, 'en', msgId);
          this.messages.push({ id: msgId, role: 'user', text: `🌐 Übersetze: "${lastAi.text.slice(0, 60)}..."`, timestamp: Date.now(), type });
          await this.sendPayload(p, msgId);
          return;
        }
      }
    }

    // Normal chat
    this.messages.push({
      id: msgId,
      role: 'user',
      text: prompt,
      timestamp: Date.now(),
      type: type
    });

    if (!customPrompt) {
      this.inputText = '';
    }

    if (this.messages.length > Constants.MAX_HISTORY) {
      this.messages = this.messages.slice(-Constants.MAX_HISTORY);
    }

    await this.sendPayload(payload, msgId);
  }

  private async sendPayload(payload: BridgePayload, msgId: string) {
    this.isLoading = true;
    this.statusText = 'Sende...';
    try {
      const code = await this.wearService!.sendJson(payload);
      if (code !== 0) {
        throw new Error(`Send code ${code}`);
      }
      this.statusText = 'Warte...';

      // Timeout
      this.timeoutId = setTimeout(() => {
        if (this.isLoading) {
          this.isLoading = false;
          this.statusText = 'Timeout';
          this.messages.push({
            id: (Date.now() + 1).toString(),
            role: 'system',
            text: '⏱️ Timeout: Keine Antwort vom Pi. Handy + Pi prüfen!',
            timestamp: Date.now(),
            type: MessageType.SYSTEM
          });
        }
      }, Constants.REQUEST_TIMEOUT_MS) as unknown as number;

    } catch (err) {
      const e = err as BusinessError;
      console.error(`[${Constants.TAG}] send failed ${e.code} ${e.message}`);
      this.isLoading = false;
      this.statusText = `Fehler ${e.code}`;
      this.messages.push({
        id: (Date.now() + 1).toString(),
        role: 'system',
        text: `Senden fehlgeschlagen: ${e.message} (Code ${e.code})`,
        timestamp: Date.now(),
        type: MessageType.SYSTEM
      });
    }
  }

  private clearHistory() {
    this.messages = [{
      id: 'welcome',
      role: 'system',
      text: '🗑️ Verlauf gelöscht. Neue Frage?',
      timestamp: Date.now(),
      type: MessageType.SYSTEM
    }];
    this.saveHistory();
  }

  build() {
    Column() {
      // Header
      Row() {
        Text(this.statusText)
          .fontSize(10)
          .fontColor(this.statusText === 'Bereit' ? '#00C853' : '#FF6D00')
          .maxLines(1)
          .layoutWeight(1)
        if (this.isLoading) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color('#2979FF')
        }
        Button('⚙️')
          .fontSize(10)
          .width(28)
          .height(22)
          .backgroundColor('#E0E0E0')
          .fontColor('#000')
          .margin({ left: 4 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
        Button('🗑️')
          .fontSize(10)
          .width(28)
          .height(22)
          .backgroundColor('#FFEBEE')
          .fontColor('#D32F2F')
          .margin({ left: 4 })
          .onClick(() => this.clearHistory())
      }
      .width('100%')
      .height(26)
      .padding({ left: 10, right: 8 })

      // Quick Actions (erweiterbar)
      if (this.showQuickActions) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(Constants.QUICK_ACTIONS, (action: any) => {
              Button(action.label)
                .fontSize(9)
                .height(24)
                .padding({ left: 8, right: 8 })
                .backgroundColor('#E3F2FD')
                .fontColor('#1976D2')
                .borderRadius(12)
                .onClick(() => {
                  if (action.type === 'summarize' || action.type === 'translate') {
                    this.sendPrompt('', action.type as MessageType);
                  } else {
                    this.inputText = action.prompt;
                  }
                  this.showQuickActions = false;
                })
            })
          }
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .height(32)
        .scrollBar(BarState.Off)
      }

      // Chat Verlauf
      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.messages, (msg: ChatMessage) => {
            Column() {
              Row() {
                Text(msg.role === 'user' ? 'Du' : msg.role === 'ai' ? 'AI' : 'Sys')
                  .fontSize(8)
                  .fontColor(msg.role === 'user' ? '#2979FF' : msg.role === 'ai' ? '#00C853' : '#9E9E9E')
                if (msg.type && msg.type !== MessageType.CHAT) {
                  Text(` ${msg.type}`)
                    .fontSize(7)
                    .fontColor('#9E9E9E')
                    .margin({ left: 4 })
                }
                Blank()
                Text(new Date(msg.timestamp).toLocaleTimeString())
                  .fontSize(7)
                  .fontColor('#BDBDBD')
              }
              .width('85%')
              .alignSelf(msg.role === 'user' ? Alignment.End : Alignment.Start)

              Text(msg.text)
                .fontSize(12)
                .fontWeight(msg.role === 'user' ? FontWeight.Medium : FontWeight.Regular)
                .maxLines(30)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding(8)
                .backgroundColor(msg.role === 'user' ? '#E3F2FD' : msg.role === 'ai' ? '#E8F5E9' : '#F5F5F5')
                .borderRadius(12)
                .width('85%')
                .alignSelf(msg.role === 'user' ? Alignment.End : Alignment.Start)

              if (msg.thinking && this.showThinking) {
                Text(`💭 ${msg.thinking.slice(0, 250)}`)
                  .fontSize(9)
                  .fontColor('#9E9E9E')
                  .margin({ top: 2 })
                  .width('85%')
                  .alignSelf(Alignment.Start)
              }
              if (msg.truncated) {
                Text('(gekürzt - max 800 Zeichen)')
                  .fontSize(7)
                  .fontColor('#FF6D00')
              }
            }
            .width('100%')
            .alignItems(msg.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
          }, (msg: ChatMessage) => msg.id)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .backgroundColor('#FAFAFA')

      // Input Area
      Row({ space: 4 }) {
        Button(this.showQuickActions ? '▼' : '▲')
          .width(28)
          .height(36)
          .fontSize(10)
          .backgroundColor('#EEEEEE')
          .fontColor('#000')
          .borderRadius(8)
          .onClick(() => {
            this.showQuickActions = !this.showQuickActions;
          })

        TextInput({ placeholder: 'Frage tippen...', text: this.inputText })
          .placeholderColor('#BDBDBD')
          .fontSize(12)
          .height(36)
          .layoutWeight(1)
          .backgroundColor('#FFFFFF')
          .borderRadius(18)
          .padding({ left: 12 })
          .maxLength(Constants.MAX_INPUT)
          .showCounter(false)
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.sendPrompt();
          })
          .enabled(!this.isLoading)

        Button() {
          Text('↑')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.inputText.trim() && !this.isLoading ? '#2979FF' : '#BDBDBD')
        .enabled(!!this.inputText.trim() && !this.isLoading)
        .onClick(() => {
          this.sendPrompt();
        })
      }
      .width('100%')
      .height(48)
      .padding({ left: 6, right: 6, bottom: 6, top: 4 })
      .backgroundColor('#EEEEEE')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
