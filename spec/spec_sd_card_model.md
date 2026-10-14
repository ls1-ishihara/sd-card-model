# 簡易SDカードVerilogモデル 機能仕様書

## STEP2: Simplified SD Card Model

---

## 1. 文書概要

### 1.1 目的

本仕様書は、RTLシミュレーション環境で使用する簡易SDカードモデルの機能およびインターフェースを定義する。

本モデルの目的は以下とする。

- SD Host Controllerの基本動作確認
- BootROMの初期化シーケンス確認
- SDカードからのブートデータ読み出し確認
- FPGA実機評価前の機能検証
- GitHub CopilotによるSystemVerilogコード生成能力の評価

本モデルは機能検証用の簡易モデルであり、SD規格への完全準拠を目的としない。

---

### 1.2 設計方針

本モデルは以下の方針で設計する。

- SD Native Modeの1-bitデータバスを既定とし、`SD_CARD_MODEL_4BIT` defineで4-bit I/Fを有効にする
- 4-bit対応ビルドでは、CARD_TRANSFER状態でCMD55 + ACMD6を受信してデータ幅を切り替える
- 読み出し専用とする
- 初期化と単一ブロック読み出しに必要なコマンドのみ実装する
- 応答レイテンシは固定値とする
- CRCフィールドは送受信するが、CRC計算および検証は行わない
- Hostは正常なコマンドシーケンスを送信するものとする
- boot.memから読み込んだデータをCMD17で返却する

---

## 2. 適用範囲

### 2.1 対応機能

- SD Native Mode
- 1-bit Data Bus
- オプションの4-bit Data Bus (`SD_CARD_MODEL_4BIT` define)
- ACMD6による1-bit/4-bitバス幅切り替え
- 48-bitコマンド受信
- SDカード初期化シーケンス
- 固定CID応答
- 固定RCA応答
- 単一ブロック読み出し
- boot.memの読み込み
- 不正コマンド検出
- コマンドおよび状態遷移のログ出力

---

### 2.2 非対応機能

- SPIモード
- 書き込み
- マルチブロック読み出し
- マルチブロック書き込み
- CMD12による転送停止
- CRC7計算および検証
- CRC16計算および検証
- エラー注入
- リトライ制御
- UHSモード
- DDR転送
- SDIO I/O機能
- 実デバイス相当のタイミング検証
- 電源投入シーケンスの厳密な再現
- カード容量の自動判定
- FATファイルシステム解析

---

# 3. Architecture Overview

## 3.1 システム全体構成

```text
+------------------+
|     BootROM      |
+--------+---------+
         |
         | Read request
         v
+------------------+
| SD Host          |
| Controller       |
+--------+---------+
         |
         | SD Native Interface
         |
         | sd_clk
         | sd_cmd
         | sd_dat[3:0] / sd_dat0
         v
+------------------+
| SD Card Model    |
|                  |
| - CMD Receiver   |
| - CMD Decoder    |
| - State Manager  |
| - Response Gen.  |
| - Data Sender    |
| - Memory Reader  |
+--------+---------+
         |
         | $readmemh
         v
+------------------+
| boot.mem         |
| Boot Image       |
+------------------+
```

---

## 3.2 各ブロックの責務

### BootROM

- SDカード初期化シーケンスを実行する
- SD Host Controllerへコマンド発行を要求する
- CMD17を使用してブートコードを読み出す
- 読み出したデータをCPU用メモリへ転送する

### SD Host Controller

- SDクロックを生成する
- CMDラインへ48-bitコマンドを送信する
- CMDラインからレスポンスを受信する
- DAT0ラインからデータブロックを受信する
- BootROMへ受信完了を通知する

### SD Card Model

- 48-bitコマンドを受信する
- コマンド番号と引数を抽出する
- カード状態を管理する
- コマンドに対応するレスポンスを生成する
- CMD17に対してboot.memのデータを送信する
- 不正な状態または非対応コマンドを検出する

### boot.mem

- ブートイメージを格納する
- 1行1バイトの16進数形式とする
- `$readmemh`でモデル内部メモリへ読み込む

---

## 3.3 推奨モジュール構成

```text
rtl/
├── sd_card_model.sv
├── sd_command_receiver.sv
├── sd_command_decoder.sv
├── sd_state_manager.sv
├── sd_response_generator.sv
├── sd_data_sender.sv
└── sd_memory_reader.sv

tb/
├── tb_sd_card_model.sv
└── boot.mem

README.md
```

初版では、すべての機能を`sd_card_model.sv`に統合してもよい。

ただし、コマンド受信、レスポンス生成、データ送信については、独立したFSMまたはサブモジュールとして分離することを推奨する。

---

# 4. 外部インターフェース

## 4.1 トップモジュール

```systemverilog
module sd_card_model #(
    parameter string IMAGE_FILE       = "boot.mem",
    parameter int    IMAGE_SIZE_BYTES = 32 * 1024 * 1024,
    parameter int    BLOCK_SIZE_BYTES = 512,
    parameter int    RESPONSE_DELAY   = 8
) (
    input  logic sd_reset_n,
    input  logic sd_clk,
    inout  wire  sd_cmd,
`ifdef SD_CARD_MODEL_4BIT
    inout  wire [3:0] sd_dat
`else
    inout  wire  sd_dat0
`endif
);
```

---

## 4.2 ポート仕様

| ポート名 | 方向 | 初期値 | 説明 |
|---|---:|---:|---|
| `sd_reset_n` | input | 0 | モデルの非同期または同期リセット |
| `sd_clk` | input | 0 | SD Host Controllerから供給されるクロック |
| `sd_cmd` | inout | Z | コマンドおよびレスポンスライン |
| `sd_dat0` | inout | Z | 1-bitビルドのデータライン |
| `sd_dat[3:0]` | inout | Z | `SD_CARD_MODEL_4BIT`ビルドの4-bitデータライン |

---

## 4.3 CMDライン制御

モデル内部では出力値と出力イネーブルを分離する。

```systemverilog
logic sd_cmd_out;
logic sd_cmd_oe;

assign sd_cmd = sd_cmd_oe ? sd_cmd_out : 1'bz;
```

Hostからコマンドを受信している間、モデルはCMDラインを駆動しない。

```text
sd_cmd_oe = 0
sd_cmd    = Z
```

レスポンス送信中のみモデルがCMDラインを駆動する。

---

## 4.4 DATライン制御

```systemverilog
logic [3:0] sd_dat_out;
logic [3:0] sd_dat_oe;

`ifdef SD_CARD_MODEL_4BIT
assign sd_dat = sd_dat_oe ? sd_dat_out : 4'bzzzz;
`else
assign sd_dat0 = sd_dat_oe[0] ? sd_dat_out[0] : 1'bz;
`endif
```

4-bitビルドではデータ幅に応じて使用するDAT線を駆動し、送信中以外は全DAT線をHigh-Zへ解放する。defineなしの1-bitビルドでは`sd_dat0`のみを公開する。

---

# 5. イメージメモリ仕様

## 5.1 ファイル名

デフォルトファイル名を以下とする。

```text
boot.mem
```

---

## 5.2 ファイル形式

1行1バイトの16進数形式とする。

```text
12
34
56
78
AA
BB
CC
DD
```

---

## 5.3 メモリ宣言

```systemverilog
logic [7:0] image_mem [0:IMAGE_SIZE_BYTES-1];
```

---

## 5.4 イメージ読み込み

```systemverilog
initial begin
    $readmemh(IMAGE_FILE, image_mem);
end
```

読み込まれていない領域は`00h`として扱うことを推奨する。

---

## 5.5 ブロック仕様

```text
ブロックサイズ : 512 bytes
アドレス方式   : Block Address
```

CMD17の引数をブロック番号として扱う。

```text
byte_address = block_address × 512
```

本モデルではSDHC相当のブロックアドレス方式に固定する。

---

# 6. コマンド受信仕様

## 6.1 コマンドフォーマット

HostからCardへのコマンドは48 bitとする。

```text
+-------+--------------+---------+----------+------+-----+
| Start | Transmission | CMD IDX | Argument | CRC7 | End |
+-------+--------------+---------+----------+------+-----+
| 1 bit | 1 bit        | 6 bit   | 32 bit   | 7 bit|1 bit|
+-------+--------------+---------+----------+------+-----+
```

ビット構成を以下とする。

```text
[47]    Start Bit
[46]    Transmission Bit
[45:40] Command Index
[39:8]  Argument
[7:1]   CRC7
[0]     End Bit
```

---

## 6.2 受信タイミング

モデルは`sd_clk`の立ち上がりエッジで`sd_cmd`をサンプリングする。

Start Bitを検出した後、48 bitをシフトレジスタへ格納する。

```systemverilog
logic [47:0] cmd_shift_reg;
```

48 bit受信後、以下を抽出する。

```systemverilog
cmd_index = cmd_shift_reg[45:40];
cmd_arg   = cmd_shift_reg[39:8];
```

CRC7は受信するが検証しない。

---

# 7. カード状態

## 7.1 状態定義

```systemverilog
typedef enum logic [2:0] {
    CARD_IDLE,
    CARD_READY,
    CARD_IDENT,
    CARD_STANDBY,
    CARD_TRANSFER
} card_state_t;
```

---

## 7.2 Expected State Diagram

```text
                 +---------+
                 |  RESET  |
                 +----+----+
                      |
                      v
                 +---------+
           +---->|  IDLE   |
           |     +----+----+
           |          |
           |    CMD55 + ACMD41
           |    Ready = 1
           |          v
           |     +---------+
           |     |  READY  |
           |     +----+----+
           |          |
           |         CMD2
           |          v
           |     +---------+
           |     |  IDENT  |
           |     +----+----+
           |          |
           |         CMD3
           |          v
           |    +-----------+
           |    |  STANDBY  |
           |    +-----+-----+
           |          |
           |         CMD7
           |          v
           |    +-----------+
           +----+ TRANSFER  |
             CMD0+-----+----+
                      |
                    CMD17
                      |
                      v
                 +-----------+
                 | TRANSFER  |
                 +-----------+
```

CMD0を受信した場合、現在状態にかかわらず`CARD_IDLE`へ戻る。

CMD17ではカード状態を変更しない。

---

## 7.3 状態別許可コマンド

| 状態 | 許可コマンド |
|---|---|
| `CARD_IDLE` | CMD0、CMD8、CMD55、ACMD41 |
| `CARD_READY` | CMD0、CMD2 |
| `CARD_IDENT` | CMD0、CMD3 |
| `CARD_STANDBY` | CMD0、CMD7 |
| `CARD_TRANSFER` | CMD0、CMD7、CMD17、CMD55、ACMD6 |

許可されていない状態でコマンドを受信した場合、`ILLEGAL_COMMAND`を含むR1レスポンスを返す。

---

# 8. 対応コマンド

## 8.1 CMD0: GO_IDLE_STATE

### 機能

カード状態および内部初期化カウンタをリセットする。

### 状態遷移

```text
ANY -> CARD_IDLE
```

### 応答

応答なし。

### 内部処理

```text
card_state       = CARD_IDLE
app_cmd_pending  = 0
acmd41_count     = 0
```

---

## 8.2 CMD8: SEND_IF_COND

### 許可状態

```text
CARD_IDLE
```

### 期待引数

```text
0x000001AA
```

### 応答

R7形式、48 bit。

応答データ部には以下を設定する。

```text
0x000001AA
```

---

## 8.3 CMD55: APP_CMD

### 機能

次に受信するコマンドをApplication Commandとして解釈する。

### 内部処理

```text
app_cmd_pending = 1
```

### 応答

R1形式。

次のコマンド受信後、`app_cmd_pending`を0へクリアする。

---

## 8.4 ACMD41: SD_SEND_OP_COND

### 判定条件

以下の両方を満たす場合にACMD41として扱う。

```text
cmd_index       = 41
app_cmd_pending = 1
```

### 初期化完了条件

1回目および2回目のACMD41ではReady Bitを0とする。

3回目以降のACMD41ではReady Bitを1とする。

```text
ACMD41 count < 3 : Ready = 0
ACMD41 count >= 3: Ready = 1
```

### 状態遷移

Ready Bitが1になった時点で以下へ遷移する。

```text
CARD_IDLE -> CARD_READY
```

### 応答

R3形式。OCRの固定値を返す。

```text
OCR = 0xC0FF8000
```

---

## 8.5 CMD2: ALL_SEND_CID

### 許可状態

```text
CARD_READY
```

### 機能

固定CIDを返す。

### 応答

R2形式、136 bit。

### 固定CID例

```text
Manufacturer ID : 0x01
Product Name    : "RTISD"
Serial Number   : 0x12345678
```

### 状態遷移

```text
CARD_READY -> CARD_IDENT
```

---

## 8.6 CMD3: SEND_RELATIVE_ADDR

### 許可状態

```text
CARD_IDENT
```

### 固定RCA

```systemverilog
localparam logic [15:0] CARD_RCA = 16'h1234;
```

### 応答

R6形式。

### 状態遷移

```text
CARD_IDENT -> CARD_STANDBY
```

---

## 8.7 CMD7: SELECT_CARD

### 許可状態

```text
CARD_STANDBY
CARD_TRANSFER
```

### 選択条件

CMD7引数の上位16 bitが固定RCAと一致すること。

```text
Argument[31:16] = 0x1234
```

### 状態遷移

```text
CARD_STANDBY -> CARD_TRANSFER
```

### 応答

R1形式。

---

## 8.8 ACMD6: SET_BUS_WIDTH

### 許可状態

```text
CARD_TRANSFER
```

CMD55の次にCMD6を受信した場合にACMD6として扱う。引数`[1:0]`が`00`なら1-bit、`10`なら4-bitを選択する。その他の値、TRANSFER以外の状態、または4-bit未対応ビルドでの4-bit要求には`ILLEGAL_COMMAND`を含むR1を返し、現在の幅を維持する。

リセットおよびCMD0後は常に1-bitである。4-bitビルドのテストベンチは初期化・CMD7選択を1-bitで行い、ACMD6のR1応答後にホスト側を4-bitへ切り替える。

### ビルド条件

```text
SD_CARD_MODEL_4BIT defineなし : sd_dat0 I/F、1-bitのみ
SD_CARD_MODEL_4BIT defineあり : sd_dat[3:0] I/F、ACMD6で1-bit/4-bit切り替え可能
```

---

## 8.9 CMD17: READ_SINGLE_BLOCK

### 許可状態

```text
CARD_TRANSFER
```

### 機能

指定されたブロックから512 byteを読み出す。

### 引数

```text
Block Address
```

### アドレス計算

```systemverilog
base_address = cmd_argument * BLOCK_SIZE_BYTES;
```

### 状態遷移

なし。

```text
CARD_TRANSFER -> CARD_TRANSFER
```

### 処理内容

1. CMD17を受信する
2. R1レスポンスを送信する
3. 固定クロック数待機する
4. 選択中のDAT線にStart Bitを送信する
5. 512 byteをMSB firstで送信する
6. Dummy CRC16を送信する
7. End Bitを送信する
8. DAT0をHigh-Zへ戻す

---

# 9. レスポンス仕様

## 9.1 CMDラインのレスポンス

R1、R3、R6、R7レスポンスは48 bitとする。

R2レスポンスは136 bitとする。

CRCは固定値でよい。

### 48-bitレスポンス共通構成

```text
Start Bit
Transmission Bit
Command Index
Response Data
Dummy CRC7
End Bit
```

### CRC7

固定値を使用する。

```text
CRC7 = 7'h00
```

### End Bit

```text
End Bit = 1
```

---

## 9.2 R1エラー

以下の場合、`ILLEGAL_COMMAND`ビットを1とする。

- 非対応コマンドを受信した
- 現在状態では許可されていないコマンドを受信した
- CMD55なしでCMD41を受信した
- CMD7のRCAが一致しなかった
- CARD_TRANSFER以外でCMD17を受信した

---

# 10. CMD17 Timing Sequence

## 10.1 基準点

CMD17タイミングのCycle 0は、CMD17の48 bit目を受信したクロックとする。

R1レスポンス送信完了後からデータ応答レイテンシをカウントする。

---

## 10.2 CMD17内部シーケンサ

```systemverilog
typedef enum logic [3:0] {
    READ_IDLE,
    READ_SEND_R1,
    READ_WAIT,
    READ_SEND_START,
    READ_SEND_DATA,
    READ_SEND_CRC,
    READ_SEND_END,
    READ_COMPLETE
} read_state_t;
```

---

## 10.3 クロック単位シーケンス

```text
CMD17受信完了
    |
    | Cycle 0
    v
+------------------+
| Decode CMD17     |
| Check card state |
| Latch block addr |
+--------+---------+
         |
         | Cycle 1
         v
+------------------+
| Send R1 response |
| 48 clocks        |
+--------+---------+
         |
         | R1送信完了
         v
+------------------+
| Response Delay   |
| 8 clocks         |
+--------+---------+
         |
         | Delay終了
         v
+------------------+
| DAT0 Start Bit   |
| 1 clock, value=0 |
+--------+---------+
         |
         v
+------------------+
| 512-byte Data    |
| 4096 clocks      |
| MSB first        |
+--------+---------+
         |
         v
+------------------+
| Dummy CRC16      |
| 16 clocks        |
+--------+---------+
         |
         v
+------------------+
| DAT0 End Bit     |
| 1 clock, value=1 |
+--------+---------+
         |
         v
+------------------+
| Release DAT0     |
| High-Z           |
+------------------+
```

---

## 10.4 タイミングチャート

```text
sd_clk
   _   _   _   _                 _   _   _   _   _
__| |_| |_| |_| |_______________| |_| |_| |_| |_| |__

sd_cmd
   <------ CMD17: 48 bits ------->
                                      <--- R1: 48 bits --->

sd_dat0
ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
                                       |<--8 CLK-->|
                                                    0
                                                    ^
                                                    Start Bit
                                                     D[7]
                                                      D[6]
                                                       ...
                                                        D[0]
                                                         ...
                                                         Byte511
                                                                  CRC16
                                                                        1
                                                                        ^
                                                                        End Bit
                                                                         Z
```

---

## 10.5 データ送信順序

512 byteのデータは、バイトアドレスの昇順で送信する。

```text
image_mem[base_address + 0]
image_mem[base_address + 1]
image_mem[base_address + 2]
...
image_mem[base_address + 511]
```

各バイトはMSB firstで送信する。

```text
bit7 -> bit6 -> bit5 -> bit4 -> bit3 -> bit2 -> bit1 -> bit0
```

---

## 10.6 データブロック構成

SD Native 1-bitモードの簡易データブロックを以下とする。

```text
+-----------+------------------+-------------+---------+
| Start Bit | Data             | Dummy CRC16 | End Bit |
+-----------+------------------+-------------+---------+
| 1 bit     | 512 × 8 bits     | 16 bits     | 1 bit   |
+-----------+------------------+-------------+---------+
| 0         | MSB first        | 16'h0000    | 1       |
+-----------+------------------+-------------+---------+
```

SPIモードの`FEh`データトークンは使用しない。

---

## 10.7 範囲外アクセス

以下の場合を範囲外アクセスとする。

```text
base_address + 511 >= IMAGE_SIZE_BYTES
```

範囲外アクセス時は512 byteすべて`00h`を送信する。

```text
00h × 512 bytes
```

R1でエラーを返す方式にはせず、データをゼロ埋めしてシーケンスを完了する。

---

# 11. リセット仕様

`sd_reset_n`が0の場合、以下を初期化する。

```text
card_state       = CARD_IDLE
read_state       = READ_IDLE
app_cmd_pending  = 0
acmd41_count     = 0
sd_cmd_oe        = 0
sd_dat0_oe       = 0
block_address    = 0
byte_count       = 0
bit_count        = 0
```

リセット解除後、モデルはCMD0受信待ちとなる。

---

# 12. ログ出力仕様

モデルは主要イベントを`$display`で出力する。

```text
[SD] RESET
[SD] CMD0 received
[SD] CMD8 arg=0x000001AA
[SD] CMD55 received
[SD] ACMD41 count=1 ready=0
[SD] ACMD41 count=2 ready=0
[SD] ACMD41 count=3 ready=1
[SD] State IDLE -> READY
[SD] CMD2 send CID
[SD] State READY -> IDENT
[SD] CMD3 RCA=0x1234
[SD] State IDENT -> STANDBY
[SD] CMD7 select RCA=0x1234
[SD] State STANDBY -> TRANSFER
[SD] CMD17 block=0
[SD] Read base address=0
[SD] Send 512 bytes
[SD] CMD17 complete
```

不正操作時は以下の形式とする。

```text
[SD][ERROR] CMD17 received in CARD_IDLE
[SD][ERROR] Unsupported command CMD24
[SD][ERROR] CMD7 RCA mismatch
```

---

# 13. テスト仕様

## TC001: リセット確認

### 操作

```text
sd_reset_n = 0
sd_reset_n = 1
```

### 期待結果

- カード状態が`CARD_IDLE`になる
- CMDおよびDAT0がHigh-Zになる
- ACMD41カウンタが0になる

---

## TC002: 初期化シーケンス

### 入力

```text
CMD0
CMD8
CMD55
ACMD41
CMD55
ACMD41
CMD55
ACMD41
CMD2
CMD3
CMD7
```

### 期待結果

```text
CARD_IDLE
-> CARD_READY
-> CARD_IDENT
-> CARD_STANDBY
-> CARD_TRANSFER
```

---

## TC003: 先頭ブロック読み出し

### 入力

```text
CMD17
Argument = 0
```

### 期待結果

```text
boot.memの先頭512 byteがDAT0から出力される
```

---

## TC004: 任意ブロック読み出し

### 入力

```text
CMD17
Argument = 100
```

### 期待結果

```text
image_mem[51200]から512 byteが出力される
```

---

## TC005: データビット順確認

### boot.mem

```text
A5
3C
```

### 期待ビット列

```text
A5 = 1 0 1 0 0 1 0 1
3C = 0 0 1 1 1 1 0 0
```

---

## TC006: 範囲外アクセス

### 入力

```text
CMD17
Argument = 最大ブロック番号を超える値
```

### 期待結果

```text
00h × 512 byte
```

---

## TC007: 状態不正

### 操作

`CARD_IDLE`状態でCMD17を送信する。

### 期待結果

- データ送信を開始しない
- R1の`ILLEGAL_COMMAND`を1にする
- カード状態を変更しない

---

## TC008: 非対応コマンド

### 操作

CMD24を送信する。

### 期待結果

- R1の`ILLEGAL_COMMAND`を1にする
- 書き込み処理を開始しない
- カード状態を変更しない

---

## TC009: RCA不一致

### 操作

CMD7で`0x1234`以外のRCAを指定する。

### 期待結果

- `CARD_TRANSFER`へ遷移しない
- R1でエラーを返す

---

## TC010: 連続CMD17

### 操作

異なるBlock AddressでCMD17を2回実行する。

### 期待結果

- それぞれのブロックデータが返る
- 各転送後も状態が`CARD_TRANSFER`に維持される

---

# 14. 受入条件

以下をすべて満たした場合、本モデルを合格とする。

- SystemVerilogコンパイルエラーがない
- CMD0により`CARD_IDLE`へ遷移する
- CMD8に対してR7レスポンスを返す
- CMD55後のCMD41をACMD41として認識する
- 3回目のACMD41でReady状態になる
- CMD2に対して固定CIDを返す
- CMD3に対して固定RCAを返す
- CMD7により`CARD_TRANSFER`へ遷移する
- CMD55後のACMD6で1-bit/4-bit幅を切り替え、CMD0で1-bitへ戻る
- CMD17に対して512 byteを返す
- CMD17のデータがboot.memと一致する
- 各バイトがMSB firstで出力される
- 4-bit時は上位/下位ニブル順で4線へ出力される
- Dummy CRC16が16 bit出力される
- 非対応コマンドに対してエラー応答する
- 範囲外アクセス時に512 byteのゼロデータを返す
- シミュレーションがハングしない

---

# 15. Copilotへの実装指示

この仕様書を読み、SystemVerilogによる簡易SDカードモデルとテストベンチを生成すること。

## 必須成果物

```text
rtl/
├── sd_card_model.sv
├── sd_command_receiver.sv
├── sd_command_decoder.sv
├── sd_state_manager.sv
├── sd_response_generator.sv
├── sd_data_sender.sv
└── sd_memory_reader.sv

tb/
├── tb_sd_card_model.sv
└── boot.mem

README.md
```

## 実装条件

- SystemVerilogで記述すること
- 合成可能性は要求しない
- DUTとなるSD Host Controllerに接続可能なinoutインターフェースとすること
- CMDラインと使用中のDATラインは出力イネーブルで制御すること
- `SD_CARD_MODEL_4BIT` defineの有無で1-bit/4-bitの外部DAT I/Fを切り替えること
- 4-bit対応ビルドではACMD6による幅切り替えを実装すること
- コマンド受信FSMとデータ送信FSMを分離すること
- CMD17の512-byteデータ送信をテストベンチで自動比較すること
- 各テストケースのPASS/FAILを表示すること
- タイムアウト監視を設けること
- すべてのテスト成功時に終了コード0相当で終了すること
- エラー発生時は該当するコマンド、状態、期待値、実測値を表示すること

---

# 16. 制約および注意事項

本モデルは簡易機能モデルであり、実SDカードとの完全互換性を保証しない。

特に以下は簡略化されている。

- CRC
- レスポンスレイテンシ
- 電源投入動作
- カード内部Busy
- CMDおよびDATラインの電気的特性
- セットアップ時間およびホールド時間
- SDクロック周波数切り替え
- カード容量情報
- 実デバイス固有応答

FPGA実機へ移行する際は、実SDカードの初期化シーケンス、CRC、タイムアウト、カード種別、ブロックアドレス方式を別途確認すること。

---

# 17. SD Native 4-bitモード拡張

## 17.1 ビルドと初期幅

`SD_CARD_MODEL_4BIT`を定義しない場合、トップのDAT I/Fは従来互換の`sd_dat0`で、4-bit要求はエラーとする。defineしたビルドでは`sd_dat[3:0]`を公開し、4-bit転送に対応する。カード幅はどちらのビルドでもリセット/CMD0後に1-bitであり、CARD_TRANSFER状態でCMD55 + ACMD6を受けて切り替える。

ACMD6のArgument[1:0]は`00`で1-bit、`10`で4-bitを指定する。その他の値、許可状態外の要求、4-bit未対応ビルドでの4-bit要求は`ILLEGAL_COMMAND`として拒否し、現行幅を維持する。CMD55はCARD_IDLEおよびCARD_TRANSFER状態で受理する。

## 17.2 データ線の並列転送

4-bit時はDAT[3:0]を同時に使用し、1クロックで4 bitを送る。各バイトは上位ニブルを先に送り、次に下位ニブルを送る。

```text
先行クロック: DAT[3:0] = byte[7:4]
次クロック  : DAT[3:0] = byte[3:0]
```

Start Bitは全使用線で0、End Bitは全使用線で1とする。Dummy CRC16は16クロック、全使用線で0を出力する。1-bit転送はStart/Data/CRC/Endの合計4114クロック、4-bit転送は1042クロックとなる。応答後の固定待ち時間は従来どおり8クロック。

4-bit時の有効データは`sd_dat[3:0]`、1-bit時は`sd_dat0`または4-bit I/FのDAT0を使用する。データ送信終了後は全DAT線をHigh-Zへ解放する。

## 17.3 追加テスト

- defineなしで初期化、ACMD6 1-bit選択、4-bit要求拒否、既存CMD17データ比較を実施する。
- `SD_CARD_MODEL_4BIT` defineありで、初期化は1-bitで行い、ACMD6による1→4→1→4-bit切替を検証する。
- CMD55なしのCMD6、および不正なACMD6幅引数はエラー応答し、現在の幅を維持する。
- 両モードで512バイト全体、バイト順、Start/End、Dummy CRC、DAT解放を比較する。
- 1-bitは4114クロック、4-bitは1042クロック、応答からデータ開始まで8クロックであることを確認する。
- CMD0で4-bit幅が1-bitへ戻ることを確認する。