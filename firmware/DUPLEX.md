# Full-duplex test firmware (one StackChan, Playkind gateway)

A build variant of this firmware that cancels the speaker's echo on the robot, so it keeps
listening while it speaks. A child can then interrupt Robo by voice, and the Playkind gateway
can run a full-duplex model (GPT-Live) for this robot. The normal build is unchanged; the
variant is meant for one test robot.

| | Stock build (`idf.py build`) | Full-duplex build (`./build_duplex.sh`) |
| --- | --- | --- |
| Echo cancellation | off | on the robot (`CONFIG_USE_DEVICE_AEC`) |
| Listening | `auto`: microphone off while Robo speaks | `realtime`: microphone stays on |
| Hello to the server | `features.mcp` | `features.mcp`, `features.device_aec` |
| Speaker volume | 0–100 % | capped (`CONFIG_STACKCHAN_AEC_MAX_VOLUME`, 70 %) |
| Version | `1.6.0` | `1.6.0.<yymmdd>.<hhmm>` (UTC build time) |

Both builds understand `{"type":"tts","state":"stop","flush":true}`: a cut (barge-in, stop)
drops the audio still queued, so Robo stops at once.

## What changed, and where

- `main/Kconfig.projbuild`: device AEC allowed for `BOARD_TYPE_M5STACK_STACK_CHAN`, and the
  menu *StackChan full duplex (test build)* with the settings below.
- `main/hal/board/cores3_audio_codec.cc`: volume cap, gain of the reference input (ES7210 MIC3),
  a level log, and a 4-slot fallback layout for the reference.
- `patches/xiaozhi-esp32.patch` (applied to xiaozhi-esp32 v2.2.4 by `fetch_repos.py`): the
  `device_aec` hello feature, the `flush` stop, and the echo-canceller, noise-suppression and
  gain-control settings in `afe_audio_processor.cc`.
- `sdkconfig.defaults.duplex`: the variant's settings. `build_duplex.sh`: builds it into
  `build-duplex/` and collects `dist/duplex-<version>/`.
- `.github/workflows/firmware.yml`: builds both variants on every push to `firmware/`; the
  duplex image is an artifact of the run.

## The echo reference

The CoreS3 wires ES7210 MIC3 to the speaker as an AEC loop (M5Stack CoreS3 FAQ). The driver
selects MIC1–MIC3, which puts the ES7210 into TDM mode, and reads a 2-slot frame. Espressif
reads its own ES7210 AEC boards (ESP32-S3-BOX, BOX-3, Korvo-2) in the TDM order MIC1, MIC3,
MIC2, MIC4, so the second slot of that frame is most likely MIC3: the reference is already
there. This is a reading of the sources, not a measurement: check it with the level log before
tuning anything.

If the log shows that the reference follows a person's voice instead of the speaker, switch
to the fallback: `CONFIG_STACKCHAN_AEC_REF_4SLOT=y` reads all four TDM slots and keeps slot 0
and `CONFIG_STACKCHAN_AEC_REF_TDM_SLOT` (try 1, 2, 3). The speaker then runs 32-bit slots, so
both I2S directions share one 64 fs bit clock, and the AW88298 amplifier is set to 32-bit input.

## Build

```bash
# ESP-IDF v5.5.4: https://docs.espressif.com/projects/esp-idf/en/v5.5.4/esp32s3/get-started/
. "$IDF_PATH/export.sh"
cd firmware
STACKCHAN_OTA_URL=https://gateway.playkind.studio/xiaozhi/<secret>/ota/ ./build_duplex.sh
```

`STACKCHAN_OTA_URL` is optional: the robot's own NVS entry (`wifi/ota_url`, written by
`stackchan-set-ota`) wins over it; the baked-in URL only helps after a factory reset.
Without ESP-IDF: take the `stackchan-duplex-firmware` artifact of the latest *StackChan
firmware* run in GitHub Actions.

## Install on the test robot

1. **Back up the whole flash first** (16 MB, cable in the base's USB-C port):

   ```bash
   python -m esptool --chip esp32s3 -p <PORT> read_flash 0 0x1000000 stackchan-flash-$(date +%F).bin
   ```

   Way back: `python -m esptool --chip esp32s3 -p <PORT> write_flash 0 stackchan-flash-<date>.bin`.

2. **Flash over USB** (writes bootloader, partition table, app and assets; not the NVS, so Wi-Fi,
   OTA address, servo calibration and binding stay):

   ```bash
   cd dist/duplex-<version>
   python -m esptool --chip esp32s3 -p <PORT> -b 460800 write_flash @flash_args
   ```

   Or `./build_duplex.sh --flash <PORT>` straight from the build.

3. **Check** on the serial monitor (`idf.py -B build-duplex monitor`): the line
   `Echo reference: 2-slot frame, slot 1, MIC3 gain 30 dB, volume cap 70%`, then
   `AEC levels: …` once a second. In the Studio (Admin → Creatures → Device →
   *Listening & firmware*) the robot shows "full duplex" after its first conversation, and the
   gateway transcript (Diagnostics) starts with `session started · <model> · full duplex`.

Later images go over the air: Device → *Listening & firmware* → upload `stack-chan.bin`. The
robot installs it on its next start (or Settings → update). If it does not boot, the bootloader
rolls back by itself; after three tries the gateway stops offering it.

## Measure, then tune (one change at a time)

The level log (`CONFIG_STACKCHAN_AEC_LEVEL_LOG=y`, on in the variant) prints once a second:

```
AEC levels: mic rms 812 peak 6120 | ref rms 2310 peak 15880 | speaker played 1000 ms
```

1. **Reference check.** Robo talks (Studio → Quick tests → *Say hello*), nobody in the room:
   `ref` must be clearly above zero while `speaker played` is high. Then a person talks, Robo
   silent: `ref` must stay near zero while `mic` rises. Otherwise: the 4-slot fallback above.
2. **Reference level.** `ref peak` near 32767 while Robo is loud: clipped, lower
   `CONFIG_STACKCHAN_AEC_REF_GAIN_DB` (30 → 21 → 12). Below about 300: raise it.
3. **Self-interruption test** (the main risk). Robo speaks 30 s at the capped volume, servos
   moving, camera on: the gateway transcript must show no `user` line and Robo must not stop.
   If it does: lower `CONFIG_STACKCHAN_AEC_MAX_VOLUME`, try
   `CONFIG_STACKCHAN_AEC_MODE_SR_HIGH_PERF`, check the robot's speaker is not touching the case.
4. **Barge-in.** A child talks over Robo: Robo must stop within half a second.
5. **Quiet voices.** A child speaks softly from 1.5 m: try `CONFIG_STACKCHAN_AEC_AGC=y`.
6. **Servo and room noise:** try `CONFIG_STACKCHAN_AEC_NS=y` (WebRTC noise suppression).
7. **CPU.** `CONFIG_FREERTOS_GENERATE_RUN_TIME_STATS` is on; with AEC, wake word, Opus, camera,
   display and servos together, watch for audio drop-outs. `CONFIG_STACKCHAN_AEC_MODE_VOIP_LOW_COST`
   saves CPU.

Change a value in `sdkconfig.defaults.duplex` and run `./build_duplex.sh` again (it rebuilds the
sdkconfig when the defaults change), or use `idf.py -B build-duplex menuconfig` → *Xiaozhi
Assistant* → *StackChan full duplex (test build)*.

Once tests 1–4 hold for several minutes, set `GATEWAY_STACKCHAN_DUPLEX_MODEL=gpt-live-1` on the
gateway: only this robot switches to GPT-Live, the stock robots stay on `gpt-realtime-2.1`.

## Back to the stock firmware

Flash the stock build (`idf.py build flash`), the factory image from M5Stack, or the full-flash
backup from step 1.
