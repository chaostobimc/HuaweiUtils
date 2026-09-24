/**
 * Settings Page - Erweiterbar für zukünftige Features
 */
import { preferences } from '@kit.ArkData';
import { Constants } from '../common/Constants';
import router from '@ohos.router';

@Entry
@Component
struct Settings {
  @State showThinking: boolean = false;
  @State maxHistory: number = Constants.MAX_HISTORY;
  @State status: string = 'Lade...';
  private prefs: preferences.Preferences | null = null;

  async aboutToAppear() {
    try {
      this.prefs = await preferences.getPreferences(getContext(this), 'ai_chat');
      this.showThinking = await this.prefs.get('showThinking', false) as boolean;
      this.maxHistory = await this.prefs.get('maxHistory', Constants.MAX_HISTORY) as number;
      this.status = 'Bereit';
    } catch (e) {
      this.status = 'Fehler beim Laden';
    }
  }

  private async save() {
    try {
      if (this.prefs) {
        await this.prefs.put('showThinking', this.showThinking);
        await this.prefs.put('maxHistory', this.maxHistory);
        await this.prefs.flush();
        this.status = 'Gespeichert ✓';
        setTimeout(() => {
          this.status = 'Bereit';
        }, 1500);
      }
    } catch (e) {
      this.status = 'Speichern fehlgeschlagen';
    }
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Button('← Zurück')
          .fontSize(12)
          .height(28)
          .onClick(() => {
            router.back();
          })
        Blank()
        Text('Einstellungen')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text(this.status)
          .fontSize(9)
          .fontColor('#00C853')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      Scroll() {
        Column({ space: 16 }) {
          // Thinking Toggle
          Row() {
            Column() {
              Text('💭 Thinking anzeigen')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
              Text('Zeigt DeepSeek Denkprozess')
                .fontSize(9)
                .fontColor('#9E9E9E')
            }
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.showThinking })
              .onChange((isOn: boolean) => {
                this.showThinking = isOn;
                this.save();
              })
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(12)

          // Info
          Column({ space: 6 }) {
            Text('ℹ️ Info')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .width('100%')
            Text(`Bundle: ${Constants.ANDROID_PACKAGE}`)
              .fontSize(9)
              .fontColor('#666')
              .width('100%')
            Text(`Max Verlauf: ${this.maxHistory}`)
              .fontSize(9)
              .fontColor('#666')
              .width('100%')
            Text(`Max Input: ${Constants.MAX_INPUT} Zeichen`)
              .fontSize(9)
              .fontColor('#666')
              .width('100%')
            Text(`Timeout: ${Constants.REQUEST_TIMEOUT_MS / 1000}s`)
              .fontSize(9)
              .fontColor('#666')
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#E8F5E9')
          .borderRadius(12)

          // Future Features
          Column({ space: 6 }) {
            Text('🚀 Zukünftige Features (erweiterbar)')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .width('100%')
            Text('• Wetter: Wetter in Berlin')
              .fontSize(9)
              .fontColor('#666')
              .width('100%')
            Text('• Übersetzen: Automatisch EN/DE')
              .fontSize(9)
              .fontColor('#666')
              .width('100%')
            Text('• Zusammenfassen: Letzte Antwort kürzen')
              .fontSize(9)
              .fontColor('#666')
              .width('100%')
            Text('• Sensoren: Herzfrequenz etc. (mit Permission)')
              .fontSize(9)
              .fontColor('#666')
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFF3E0')
          .borderRadius(12)

          Button('Verlauf löschen')
            .width('100%')
            .height(36)
            .backgroundColor('#FFEBEE')
            .fontColor('#D32F2F')
            .fontSize(12)
            .onClick(async () => {
              if (this.prefs) {
                await this.prefs.put('history', '[]');
                await this.prefs.flush();
                this.status = 'Verlauf gelöscht ✓';
              }
            })

          Text('Private AI Assistent v1.0\nGT6 + Pi5 + Android\nAkku optimiert, erweiterbar')
            .fontSize(8)
            .fontColor('#BDBDBD')
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(12)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
