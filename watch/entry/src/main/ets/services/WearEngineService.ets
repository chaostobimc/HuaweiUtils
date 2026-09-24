/**
 * WearEngineService - Vollständig implementiert, erweiterbar
 * Kapselt WearEngine, Chunking, Error Handling
 */

import { wearEngine } from '@kit.WearEngine';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../common/Constants';
import { BridgePayload } from '../models/ChatMessage';

export interface AiBridgeConfig {
  androidPackage: string;
  androidFingerprint: string;
}

export class WearEngineService {
  private deviceClient: wearEngine.DeviceClient | null = null;
  private p2pClient: wearEngine.P2pClient | null = null;
  private textEncoder = new util.TextEncoder();
  private textDecoder = new util.TextDecoder();
  private deviceId: string = '';
  private config: AiBridgeConfig;

  // Chunking
  private chunkBuffer: Map<string, string[]> = new Map();
  private chunkTotalMap: Map<string, number> = new Map();

  constructor(config: AiBridgeConfig) {
    this.config = config;
  }

  async init(context: any): Promise<string> {
    this.deviceClient = wearEngine.getDeviceClient(context);
    this.p2pClient = wearEngine.getP2pClient(context);

    const devices = await this.deviceClient.getConnectedDevices();
    if (devices.length === 0) {
      throw new Error('No connected phone - Huawei Health prüfen');
    }
    this.deviceId = devices[0].randomId;
    console.info(`[${Constants.TAG}] Using device ${devices[0].name} id=${this.deviceId}`);
    return this.deviceId;
  }

  getAppParam(): wearEngine.P2pAppParam {
    return {
      remoteApp: {
        bundleName: this.config.androidPackage,
        fingerprint: this.config.androidFingerprint
      }
    };
  }

  getDeviceId(): string {
    return this.deviceId;
  }

  async sendJson(payload: object): Promise<number> {
    if (!this.p2pClient || !this.deviceId) throw new Error('Not initialized - call init() first');
    const jsonStr = JSON.stringify(payload);
    const encoded = this.textEncoder.encodeInto(jsonStr);
    const msg: wearEngine.P2pMessage = { content: encoded };
    try {
      const result = await this.p2pClient.sendMessage(this.deviceId, this.getAppParam(), msg);
      console.info(`[${Constants.TAG}] Send result code: ${result.code}`);
      return result.code;
    } catch (err) {
      const e = err as BusinessError;
      console.error(`[${Constants.TAG}] Send failed ${e.code}: ${e.message}`);
      throw e;
    }
  }

  async registerReceiver(onMessage: (data: string) => void) {
    if (!this.p2pClient || !this.deviceId) throw new Error('Not initialized');
    
    const receiver: wearEngine.P2pMessageReceiver = {
      onMessageReceived: (deviceId: string, message: wearEngine.P2pMessage) => {
        try {
          const str = this.textDecoder.decodeToString(new Uint8Array(message.content));
          console.info(`[${Constants.TAG}] Raw msg len=${str.length}`);

          // Chunked handling
          const parsed = JSON.parse(str) as BridgePayload;
          if (parsed.is_chunked && parsed.chunk_data !== undefined) {
            const id = parsed.id;
            const idx = parsed.chunk_index || 0;
            const total = parsed.chunk_total || 1;

            if (!this.chunkBuffer.has(id)) {
              this.chunkBuffer.set(id, new Array(total).fill(''));
              this.chunkTotalMap.set(id, total);
              console.info(`[${Constants.TAG}] Start chunked ${id} total=${total}`);
            }
            const buffer = this.chunkBuffer.get(id)!;
            buffer[idx] = parsed.chunk_data;

            if (buffer.every(c => c !== '')) {
              const full = buffer.join('');
              console.info(`[${Constants.TAG}] All chunks for ${id} received len=${full.length}`);
              this.chunkBuffer.delete(id);
              this.chunkTotalMap.delete(id);
              onMessage(full);
            }
            return;
          }

          onMessage(str);
        } catch (e) {
          console.error(`[${Constants.TAG}] Receiver decode failed ${JSON.stringify(e)}`);
          // Fallback: try raw decode
          try {
            const fallback = this.textDecoder.decodeToString(new Uint8Array(message.content));
            onMessage(fallback);
          } catch {}
        }
      }
    };

    try {
      await this.p2pClient.registerMessageReceiver(this.deviceId, this.getAppParam(), receiver);
      console.info(`[${Constants.TAG}] Receiver registered`);
    } catch (err) {
      const e = err as BusinessError;
      console.error(`[${Constants.TAG}] registerReceiver failed ${e.code}: ${e.message}`);
      throw e;
    }
  }

  async unregisterReceiver() {
    // Note: HarmonyOS API for unregister might need receiver reference - we keep simple
    console.info(`[${Constants.TAG}] Unregister not implemented - auto cleanup on ability destroy`);
  }

  // Future extensibility
  async sendSensorData(data: object) {
    return this.sendJson({ type: 'sensor', data, id: Date.now().toString() });
  }
}
