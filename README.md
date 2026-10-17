# ReaScratch — REAPERだけで動く音MADスクラッチ（配布キット）

<!-- make_manual_pdf.py が作るファイル。直すときは説明書の正本を直して作り直す -->

> **説明書は `ReaScratch_manual.pdf` です。** 使い方・画面の各部・パラメーター・機材の設定（プリセット一覧）・パターン・負荷試験などは、すべてそちらにあります（画面の説明の画像入り、文字をコピーできます）。このREADMEは、その中から同梱ファイル・セットアップ手順・困ったときの表だけを抜き出したものです。

DJコントローラーのジョグホイール（またはロータリーエンコーダー・ノブ）を操作し、**音程を変えずに音声をスクラッチ**しながら、**再生位置に対応した映像コマをREAPERの動画ウィンドウに表示**するツールキットです。

REAPER 7.x（Windows / macOS）単体で動作します。基本の機能には、追加の拡張機能や外部FFmpegの導入は不要です（LOADボタンなど一部の機能で使うものは、「セットアップ手順」の「用意するもの」を参照してください）。

---

## 同梱ファイル一覧

| フォルダ / ファイル名 | 役割・内容 |
|---|---|
| `Effects/ReaScratch/reascratch.jsfx` | スクラッチ音声エンジン本体（JSFXプラグイン） |
| `Effects/ReaScratch/reascratch_cue.jsfx` | ヘッドホン用のミックス（`Cue`トラックに入る。Cueとメインの音を混ぜる`Cue mix`のつまみ。メトロノームの音は`Cue mix`の位置に関係なく足します） |
| `Effects/ReaScratch/reascratch_perf.jsfx` | 演奏の列（`DJ performance lanes`）。セットアップが各デッキのエンジンのトラックに入れ、録音中のデッキの操作をREAPERの時間軸に記録して、演奏の再生モードで鳴らします（「演奏をREAPERの時間軸に記録して再生する」） |
| `Effects/ReaScratch/reascratch_logo.png` | プラグイン画面のタイトルロゴ画像（JSFXと同じフォルダに置く。無い場合は通常の文字で表示されます） |
| `Effects/ReaScratch/`のそのほかの画像（`tex_front.png`・`knob_big.png`・`platter.png`など`*.png`） | プラグイン画面のUI用画像（外枠・パネル・つまみ・表示灯・スイッチ・TBKgaoロゴ印・レコード盤・helpの透かし）。JSFXと同じフォルダに置く。画像がない場合は、簡易表示で動作します |
| `Effects/ReaScratch/LICENSE_Saike_filters.txt` | JSFXのDJフィルターの移植元（SaikeのJSFX、Joep Vanlier）のライセンス（MIT） |
| `Effects/ReaScratch/LICENSE_ntsc_zhuker.txt` | 映像エフェクトVHSの移植元（zhukerのntsc）のライセンス（Apache 2.0） |
| `Scripts/ReaScratch/reascratch_setup.lua` | 初期セットアップ。トラック作成・JSFX読み込み・各スクリプトの登録を行います |
| `Scripts/ReaScratch/reascratch_import_video.lua` | 動画の取り込み。配置と同時にWAVを抽出し（ffmpegがあればffmpeg、なければREAPER標準機能）、JSFXへ読み込ませます。抽出した音声が途中から最後まで無音の場合は通知します |
| `Scripts/ReaScratch/reascratch_reencode_mjpeg.lua` | 動画を全コマキーフレーム（AVI/MJPEG）へ再エンコードして差し替えます（ffmpegがあればffmpeg、なければREAPER標準機能） |
| `Scripts/ReaScratch/reascratch_video_sync.lua` | スクラッチ位置と動画ウィンドウの同期スクリプト。動作中はREAPER本体の再生・一時停止をすぐ止めます（映像と音声のずれを防ぐため。録音は止めない）。再実行で停止。セットアップで「はい」ならREAPER起動時に自動で開始 |
| `Scripts/ReaScratch/reascratch_video_reopen.lua` | 動画ウィンドウを再表示します（モニターやプロジェクターの電源操作や抜き差し後に、動画ウィンドウが停止した場合に使用。全画面表示は維持されます） |
| `Scripts/ReaScratch/reascratch_load_test.lua` | 負荷試験（約40秒）。各デッキが自動でスクラッチし、音切れ回数・JSFXの負荷・画面描画の停止を測って、結果をテキストファイルに保存します。詳細は「性能の低いPCで試す（負荷試験）」を参照 |
| `Scripts/ReaScratch/reascratch_pattern.lua` | スクラッチパターンをデッキに配置します（エンベロープのオートメーションアイテムとして）。詳細は「エンベロープでスクラッチ（パターン）」を参照 |
| `Scripts/ReaScratch/reascratch_pattern_save.lua` | 自分で組み替えたパターンを名前を付けて保存し、パターンのメニューに加えます |
| `Scripts/ReaScratch/reascratch_record_lanes.lua` | 録音中の演奏をエンベロープに書き込むかどうかを切り替えます（既定はオン）。詳しくは「演奏を録ってエンベロープに書き込む」 |
| `Scripts/ReaScratch/reascratch_take.lua` | 演奏の収録（デッキごとの音声・映像、画面どおりの完成形）をオン/オフします。詳細は「演奏を収録する」を参照 |
| `Scripts/ReaScratch/reascratch_perf_play.lua` | 演奏の再生モード（ツールバーの`PERF PLAY`）をオン/オフします。オンのあいだ、REAPERの再生で演奏の列を鳴らします。詳細は「演奏をREAPERの時間軸に記録して再生する」を参照 |
| `Scripts/ReaScratch/reascratch_perf_play_decks.lua` | 演奏の再生モードで鳴らすデッキ（両方・デッキAだけ・デッキBだけ）を選びます |
| `Scripts/ReaScratch/reascratch_export.lua` | デッキの素材のホットキュー・メモリーキュー・CUE・BPM・拍の位置・キーを、rekordbox用のXMLかReaScratch専用の曲データに書き出します。詳細は「曲データの書き出し」を参照 |
| `Scripts/ReaScratch/reascratch_rekordbox.lua` | rekordboxで書き出したXML、Traktorの`collection.nml`、VirtualDJの`database.xml`のどれかを選び、ホットキュー・メモリーキュー・BPM・拍の位置・キーを素材に読み込みます。詳細は「rekordboxのキューを読み込む」を参照 |
| `Scripts/ReaScratch/reascratch_patterns.lua` | 付属のスクラッチパターン集（ベイビー、チャープ、ティア、フレア、クラブ、トランスフォーマー、スタッター、フリーズなど。直接実行不要） |
| `Scripts/ReaScratch/reascratch_deck_mix.eel` | デッキBの映像をデッキAの映像に重ねるVideo processorのコード。セットアップ時に`video`トラックのVideo processorへ自動登録されます（直接開く必要はありません） |
| `Scripts/ReaScratch/reascratch_lib.lua` | スクリプト群の共通ライブラリ（直接実行不要） |
| `Scripts/ReaScratch/reascratch_browser.lua` | LOADボタン（LOADのある機種）で、Media Explorerで選んだファイルをデッキに読み込みます。JSFX画面へドラッグしたファイルの読み込みと、`P`キーの試聴も行います（同期スクリプトが呼ぶため直接実行不要。LOADボタンにはjs_ReaScriptAPI拡張、試聴にはjs_ReaScriptAPI拡張とSWS拡張が必要。ドラッグでの読み込みには拡張は要りません） |
| `Scripts/ReaScratch/reascratch_black.png` | 空の素材（空にした素材・まだ何も入れていない素材）の場所に置く黒い画像。動画ウィンドウに前の映像が残らないようにします（スクリプトが使います） |
| `Scripts/ReaScratch/reascratch_audio_only.avi` | 音だけの素材の場所に置く、回るスピーカーの動画。レコード盤の回転に合わせて回ります（スクリプトが使います） |
| `Scripts/ReaScratch/reascratch_lights_off.ps1` | REAPERを閉じたあと、コントローラーの明かりをすべて消す小さなプログラム（Windows）。動画同期のスクリプトが起動すると一緒に立ち上がり、REAPERが閉じるのを待ちます |
| `Scripts/ReaScratch/reascratch_ctl_presets.lua` | setup画面の`Learn`タブで作った機材のプリセットを書き出し・読み込みます（同期スクリプトから呼ばれるため直接実行不要）。保存先はREAPERの設定フォルダの`Data/ReaScratch_controllers/`（`機種名.reascratch-preset`） |
| `ProjectTemplates/ReaScratch.RPP` | セットアップ済みプロジェクトテンプレート |
| `Data/ReaScratch/reascratch_screenset.ini` | ReaScratchのウィンドウ配置（REAPERのウィンドウセット）。セットアップの「ReaScratch のウィンドウ配置を使いますか？」に「はい」と答えると、ウィンドウセットに加わります |
| `Data/ReaScratch_samples/` | JSFXが読み込むWAVの保存フォルダ（取り込みスクリプトが自動で書き出します）。`(empty).wav`は空の素材の目印（無音のファイル。削除しても、セットアップや取り込みで作り直されます）。`rs_load_a1.wav`〜`rs_load_b8.wav`はLOADボタンで読み込む音の置き場です（セットアップが作ります）。`rs_load_a1_src.txt`などは、その音がどの素材から作られたかの記録です |
| `tools/allintra_ffmpeg.cmd` / `.command` | （予備）FFmpeg環境がある方向けの変換スクリプト |
| `HID bridge/` | NI Traktor Kontrol S2・S3・S4（HID）をMIDIに変えるプログラム一式（中身は表の下）。詳細は「HIDの機材をつなぐ（NI Traktor Kontrol S4・S3・S2）」を参照 |
| `ReaScratch_manual.pdf` | 説明書（この文書の全文に、画面の説明の図とプリセット一覧を加えたもの。文字の検索・コピーができ、目次から各章へ移動できます） |
| `README.md` | セットアップ手順とトラブルシューティングだけを抜き出した短い案内 |
| `ReaScratch_manual_en.pdf`・`README_en.md` | 英語版の説明書と短い案内 |
| `ReaScratch_screenshot.png`・`ReaScratch_screenshot_en.png` | セットアップを終えたREAPERの画面の例（ツールバー3・動画ウィンドウ・デッキA・BのJSFX画面）。REAPERの表示が日本語のもの・英語のもの |
| `LICENSE`・`CREDITS.md` | ライセンス（GNU GPL v3.0 or later）とクレジット |

**`HID bridge/`の中身**: `hid_bridge.py`、`ReaScratch-HID-Bridge.exe`（Windows）、`build_mac.command`・`run_mac.command`（macOS）、動作の報告を作る`report_windows.cmd`・`report_mac.command`、exeに入っている部品のライセンス`THIRD_PARTY_LICENSES.txt`。

---

## セットアップ手順

### 用意するもの

- **REAPER 7.x**（Windows / macOS。動作を確かめたのは7.80）
- **MIDIコントローラー**（ない場合は、マウスとキーボードで操作できます）。機種によっては、メーカーのドライバーが必要です。
  - Reloop Buddy（Windows）: Reloopの「ASIO Driver」が必要です。入れていない場合、ジョグやボタンが反応しません（「トラブルシューティング」）。
  - Herculesの一部の機種・CDJなど: 「プリセット一覧」の表の「準備」と「機種ごとの説明」に書いてあります。
  - NI Traktor Kontrol（HID）: 付属の`HID bridge`とloopMIDIを使います（「HIDの機材をつなぐ」）。
- **あれば使うもの**（ない場合も、基本の機能は使用できます）
  - ffmpeg: 動画の取り込みと全コマキーフレームへの変換で、元の動画とコマがずれないように変換します。演奏の収録で動画も作ります。探す場所は「動画が重い場合」を参照してください。
  - js_ReaScriptAPI拡張（ReaPackで入れます）とffmpeg: LOADボタン（Media Explorerから読み込む）に必要です。LOADボタンはWindowsだけで動きます。
  - js_ReaScriptAPI拡張とSWS拡張（どちらもReaPackで入れます）: Media Explorerのファイルの試聴（`P`キー）に必要です。
  - ffmpeg: JSFX画面へファイルをドラッグして読み込むときに必要です（js_ReaScriptAPI拡張は要りません）。LOADボタンと同じく、Windowsだけで動きます。

### 1. ファイルの配置

1. 使用するMIDIコントローラーをPCに接続し、REAPERを起動します。
2. REAPERのメニューから`Options` > `Show REAPER resource path in explorer/finder`を選びます。REAPERのプラグインやスクリプトが保存されている**REAPERの設定フォルダ**が開きます（中に`Effects`や`Scripts`というフォルダがあります）。
3. その設定フォルダの中に、本キットの**`Effects` / `Scripts` / `Data` / `ProjectTemplates`**の4フォルダをそのままコピー（同名フォルダに統合）します。
   - **macOSの注意**: Finderで同名のフォルダの上にドラッグすると、既定では「置き換え」になり、設定フォルダにもともとあった`Scripts`などの中身が消えます。**Optionキーを押しながらドラッグし、「結合」を選んでください**（「結合」が出ないときは、4フォルダを開いて中身をそれぞれの同名フォルダへコピーします）。
4. REAPERを再起動します。

### 2. 初期セットアップ

1. REAPERメニュー`Options` > `Preferences` > `Audio` > `MIDI Inputs`を開き、使用するコントローラーのMIDI入力が有効（Enabled）になっていることを確認します。
   - コントローラーのボタンを光らせるには、`MIDI Outputs`でも同じコントローラーを有効にしておきます。セットアップが、デッキのトラックのMIDIの出力先をそこに設定します（あとから有効にしたときは、セットアップをもう一度実行します。「ボタンを光らせる」を参照）。
2. メニュー`Actions` > `Show action list...`を開きます。
3. `New action...` > `Load ReaScript...`をクリックして`Scripts/ReaScratch/reascratch_setup.lua`を読み込み、リストで選択して`Run`をクリックします。
   - 最初に（JSFXが入っているかを確かめたあと）、メッセージの言語を選ぶメニュー「言語 / Language（ReaScratch のメッセージ）」が出ます。選択肢は`自動（REAPER の言語パックに合わせる: …）`（…は今`自動`で選ばれる言語）・`English`・`日本語`の3つで、今の設定に印が付きます（英語の表示では`Auto (follows REAPER's language pack: …)`）。`自動`は、REAPERで選んでいる言語パック（reaper.iniの`[REAPER]`の`langpack=`）のファイル名で決まります。日本語のもの（`Japanese`・`jpn`を含む、`ja_`・`jp_`などで始まる、`日本`を含む）なら日本語、それ以外（言語パックを使っていないときも）は英語です。選ばずにメニューを閉じると今の設定のままです。設定はこのPCのREAPERに保存されてすべてのプロジェクトに効き、このセットアップの続きと各スクリプトのメッセージがその言語になります。メニューはセットアップを実行するたびに出ます。
   - `video`、`audio`、`scratch engine`の3トラックが自動生成され、`scratch engine`にJSFXがインサートされます。
   - `scratch engine`のMIDI入力は「すべてのMIDI入力」になります。機種の選択はJSFXの`Preset`（後述）で行います。
   - 他のスクリプト群も自動的にアクションリストに登録されます（検索欄で「`reascratch`」と検索できるようになります）。
   - 「2つ目のデッキ（デッキB）を作りますか？」と聞かれます。「はい」で、`video B`・`audio B`（どちらも消音）・`scratch engine B`（デッキBのJSFX）・`video B view`（デッキBの映像を映すトラック。プロジェクトの映像の設定に合わせて、`video`のすぐ上か下）の4トラックと、`video`トラックのVideo processor（2つの映像を重ねる）ができます。「いいえ」を選択した場合はプロジェクトに設定が保持され、以降はそのプロジェクトで確認ダイアログは表示されません（後から追加する場合は、`scratch engine B`という名前の空トラックを作成した上でセットアップを実行してください）。詳細は「2デッキで映像を重ねる（デッキB）」を参照してください。
   - ヘッドホン用の`Cue`トラックができます。マスターには送らず、ヘッドホンの出力へ直接出します。出力の名前に「Phones」などが付いていればそれを使い、なければ出力の一覧が出るので、ヘッドホンにつながるものを選んでください（例: RME Fireface UCX IIは`Analog 7 / Analog 8`）。選択した出力先はPCのREAPER設定に保存され、次回以降は確認されません。詳細は「ヘッドホンでデッキを聴く（Cue）」を参照してください。
   - 「変換する動画の高さ」を聞かれます（入力の欄に720・540・360のどれかを入れます。ほかの数は、いちばん近いものになります。既定は720）。動画を全コマキーフレームに変換するときの高さで、小さいほど映像の処理が軽く、粗くなります。性能の低いPCでは540や360を選んでください。設定値はPCのREAPER設定に保持され、すべてのプロジェクトに適用されます（キャンセルした場合は現在の設定を維持します）。
   - REAPERが映像を先に描いてためておく設定（REAPERの既定）のときは、「REAPERが映像を先に描いてためておく設定になっています。」と知らせが出ます。このままだと、クロスフェーダーや映像エフェクトが画面に出るのが0.2〜0.5秒ほど遅れます。動画ウィンドウ（`View` > `Video`）を右クリックし、`Performance tweaks (experimental)` > `Video cache` > `All media and video FX are not cached`（日本語の画面では「パフォーマンス調整」→「ビデオキャッシュ」→「すべてのメディアおよびビデオFXはキャッシュされません」）を選んでください。すぐに効き、REAPERの再起動は必要ありません。
   - 次に「REAPER を起動したときに、動画の同期（reascratch_video_sync.lua）を自動で始めますか？」と確認されます。**「はい」の選択を推奨します**。REAPERの`Scripts/__startup.lua`（REAPERが起動のたびに実行するファイル）に数行が追記され、以後は同期スクリプトを手動で起動する必要はありません。ReaScratchの入ったプロジェクトを開くだけで、映像が自動追従します。ReaScratchの入っていないプロジェクトでは何もしません。自動同期をやめたいときは、セットアップをもう一度実行して「いいえ」を選ぶと、追加された行のみが削除されます（`__startup.lua`の他の内容はそのまま残ります）。
   - 続けて「ReaScratch のウィンドウ配置を使いますか？」と聞かれます。「はい」で、ツールバー3にReaScratchのボタン10個（SETUP・IMPORT VIDEO・MJPEG・VIDEO SYNC・VIDEO REOPEN・PATTERN・PATTERN SAVE・REC LANES・TAKE・PERF PLAY）が入り、ウィンドウセット「ReaScratch」（左上にこのツールバー、右上に16:9の動画ウィンドウ）が空いている番号に加わります。ツールバー3にほかのボタンが入っているとき、またはウィンドウセット#01〜#10がすべて使われているときは、入れ替えてよいかを確認します（入れ替えるときは、前の内容を控えます。「使う環境で気をつけること」を参照）。REAPERはウィンドウセットを起動時に読むので、**REAPERを再起動してから**、アクション`スクリーンセット: ウィンドウセット #NN をロード`（英語: `Screenset: Load window set #NN`。NNはメッセージに出る番号）で切り替えてください。前の配置には、同じ種類のアクションで戻せます。
4. メニュー`View` > `Video`で動画ウィンドウを開いておきます。
5. 使うコントローラーを選びます。`scratch engine`トラックの[FX]ボタンでJSFX画面を開き、下の隅の`setup`を押して、`Preset`のメニューから機種を選びます（メーカー → 機種 → `deck 1` / `deck 2`の順。「プリセット一覧」を参照）。`setup`はふだん右下で、デッキBを作ったときのデッキAの画面は左右が逆の並びなので左下です。デッキBを作ったときは、`scratch engine B`のJSFX画面で`deck 2`を選びます。プリセットのない機種は、setupの`Learn`タブで作れます（「触って確かめる・プリセットを作る」を参照）。コントローラーを使わないときは`Custom`のままで構いません。

> **Tips: 次回以降のプロジェクト作成**
> 一度セットアップを実行した後は、メニュー`File` > `Project templates` > `ReaScratch`から直接開始できます（テンプレートにはデッキAの`scratch engine`のみ含まれます。デッキB・`Cue`トラック・コントローラーのボタンの明かり（MIDIの出力先）は、テンプレートから開いた後にセットアップを実行すると作成・設定されます）。

### ReaScratchのボタン（ツールバー3）

ウィンドウ配置に「はい」と答えると、ウィンドウセット「ReaScratch」の左上に、次の10個のボタンが並びます（REAPERのツールバー3です。ほかのウィンドウ配置でも、アクション`Toolbar: Open/close toolbar 3`で開けます）。どのボタンも、アクションの一覧から同じ名前のスクリプトを実行するのと同じです。

| ボタン | 実行するスクリプト | 働き |
|---|---|---|
| `SETUP` | `reascratch_setup.lua` | 初期セットアップ（このページの手順）。何度実行しても構いません（デッキBや`Cue`トラックを足す、MIDIの出力先を付け直す、メッセージの言語を変えるなど） |
| `IMPORT VIDEO` | `reascratch_import_video.lua` | 動画を素材に取り込みます（「Step 1: 動画の読み込み」） |
| `MJPEG` | `reascratch_reencode_mjpeg.lua` | 動画を全コマキーフレーム（AVI/MJPEG）に変換して差し替えます。選んだ動画アイテムを変換し、何も選んでいなければデッキAの今の素材の動画を変換します（「動画が重い場合」） |
| `VIDEO SYNC` | `reascratch_video_sync.lua` | 動画同期の開始／停止を切り替えます（「Step 2: 同期の開始」） |
| `VIDEO REOPEN` | `reascratch_video_reopen.lua` | 止まった動画ウィンドウを開き直します（「プロジェクターに映す」） |
| `PATTERN` | `reascratch_pattern.lua` | スクラッチのパターンをデッキに置きます（「パターンを置く」） |
| `PATTERN SAVE` | `reascratch_pattern_save.lua` | 組み替えたパターンを名前を付けて保存します（「組み替えたパターンを保存する」） |
| `REC LANES` | `reascratch_record_lanes.lua` | 録音中の演奏をエンベロープに書き込むかを切り替えます。オンのあいだボタンが点灯します（既定はオン。「演奏を録ってエンベロープに書き込む」） |
| `TAKE` | `reascratch_take.lua` | 演奏の収録をオン／オフします。オンのあいだボタンが点灯します（「演奏を収録する」） |
| `PERF PLAY` | `reascratch_perf_play.lua` | 演奏の再生モードをオン／オフします。オンのあいだボタンが点灯します（「演奏をREAPERの時間軸に記録して再生する」） |

---

## トラブルシューティング

| 症状 | 主な原因 | 対処法 |
|---|---|---|
| **音が出ない** | モニター設定 / ファイル未読込 | - `scratch engine`トラックの録音アーム（赤丸）と入力モニター（スピーカー）がONか確認する。<br>- JSFX画面の波形の窓に波形が出ているか確認する（「no sample」なら取り込みを実行）。<br>- `Untouched transport`が`Stop`だと、ジョグに触れていない間は音が出ません。 |
| **ノブを止めると0.15秒で音が消える** | タッチモードの設定 | - タッチセンサー付き機材: `Touch note`を正しいNote番号（FLX4なら54）に設定してください。<br>- タッチセンサーなし機材: 標準の動作です。停止中も鳴らし続けるには`Auto release`を`0`にしてください（`Release note`のボタンで止めます）。 |
| **ジョグを押さえてもスクラッチにならない（タッチが効かない）** | 機材側のジョグのモード | VINYL（スクラッチ）モードの切り替えがある機種は、ONか確認してください（OFFだと天面のタッチが送られず、ピッチの微調整になる機種があります）。天面を押さえてJSFXの表示灯`touch`が光れば届いています |
| **末尾まで進めると無音になる** | 終端処理の設定 | `At end of sample`が`Stop (silent)`のとき、手を離した状態で末尾に着くと無音になります（触れていれば末尾の粒が鳴り続け、戻せます）。先頭から鳴らし続けるには`Loop to start`にしてください。 |
| **プロジェクター・モニターの電源や抜き差しのあと、動画ウィンドウが止まった** | REAPERの動画ウィンドウの描画が止まった | `reascratch_video_reopen.lua`を実行して動画ウィンドウを開き直します（「プロジェクターに映す」） |
| **映像が追従しない** | 同期スクリプト未実行 | - `reascratch_video_sync.lua`が実行中か確認してください（切り替え式で、再度実行すると停止します。自動同期にしていても、手で一度実行すると止まります）。<br>- `View` > `Video`で動画ウィンドウが開いているか確認してください。 |
| **`ReaScratch-HID-Bridge.exe`や`.command`を開くと警告が出て起動しない** | 署名のないプログラムをWindows・macOSが止めている | 「HIDの機材をつなぐ」の「警告が出て起動できないとき」を参照 |
| **クロスフェーダー・映像エフェクトが映像に遅れて出る** | REAPERが映像を先に描いてためている | 動画ウィンドウを右クリック → `Performance tweaks (experimental)` → `Video cache` → `All media and video FX are not cached`を選びます（日本語の表示は表の下）。すぐに効きます（setupも、この設定でないときは知らせます） |
| **映像のシークがカクつく** | キーフレーム間隔が広い | H.264等の圧縮動画のままになっています。「動画が重い場合」の手順でMJPEGへ変換してください。 |
| **音が途切れる・ノイズ（プチプチ音）が発生する** | PCの処理負荷過多 | 「性能の低いPCで試す（負荷試験）」の手順で測定してください。音声バッファサイズを拡大する、setupで動画の高さを小さくする、他の常駐ソフトを終了するなどの対策で改善します。 |
| **取り込んだ音声が途中から無音になる** | 旧バージョンの動画同期スクリプト | 取り込み時に警告が表示されます。旧バージョンの動画同期スクリプトがREAPERのレンダリング中に再生を停止させていたことが原因です。キットを最新版に更新し、動画を取り込み直してください。 |
| **曲の途中から先が再生されない・波形が途中で切れる** | 曲が長すぎる | 波形の窓に赤字で「only the first ○:○○ of ○:○○ loaded」と表示されている場合、読み込める長さを超えています。動画を短く切ってから取り込み直してください。 |
| **Reloop Buddyを回しても反応しない（Windows）** | MIDIドライバーの動作不全 | Windows標準ドライバーでは、BuddyのMIDI（ジョグ・ボタン）が起動しません（デバイスマネージャーで「コード10」）。Reloop製品ページの「ASIO Driver」をインストールし、Buddyを再接続してください（確かめ方は表の下）。Macでは不要です。 |
| **2デッキで、デッキBの映像が重ならない・止めると乱れる・映像エフェクトがBに効かない** | プロジェクトの映像の設定 | キットのテンプレート（`File` > `Project templates` > `ReaScratch`）から作ったプロジェクトでは起きません。いまのプロジェクトでは、`reascratch_setup.lua`をもう一度実行してください（`video B view`トラックを、プロジェクトの映像の設定に合う位置へ動かします。動画同期を起動し直しても同じです）。それでも直らないときは、REAPERを閉じて.rppをテキストエディタで開き、`VIDEO_CONFIG`で始まる1行を消して保存し、開き直してください（原因は表の下）。 |
| **JSFXが見つからない** | 配置場所の誤り | `Effects/ReaScratch/reascratch.jsfx`が、REAPERの設定フォルダ（`Options` > `Show REAPER resource path in explorer/finder`で開くフォルダ）の`Effects`の中にあるか確認してください。 |

**クロスフェーダー・映像エフェクトが映像に遅れて出る**: 日本語の表示では、`Performance tweaks (experimental)`は「パフォーマンス調整」、`Video cache`は「ビデオキャッシュ」、`All media and video FX are not cached`は「すべてのメディアおよびビデオFXはキャッシュされません」です。

**Reloop Buddyを回しても反応しない**: REAPERの`Options` > `Preferences` > `Audio` > `MIDI Inputs`に`Reloop Buddy In`が表示されれば使用可能です。

**2デッキで、デッキBの映像が重ならない**ときの原因: REAPERの映像の設定（`Project settings`の`Video`）によっては、上のトラックの映像が下のトラックを覆います。セットアップと動画同期は`video B view`を合う位置に置きます。ただし、トラックを手で並べ替えたときなどは、`video B view`トラックの映像がそのまま映り、2つの映像を重ねる処理（`video`トラックのVideo processor）を隠すことがあります。

---

## 動作確認環境

- **OS / ホスト**: Windows 11 / REAPER 7.80（FFmpegなしの状態でAVI/MJPEGの書き出し・再生を確認）
- **検証機材**: Akai APC40 mkII（実機）、Reloop Buddy（実機でMIDIの割り当てを確認。Windowsは要ドライバー）、Pioneer DDJ-FLX4（実機で試したのは開発の初期だけで、今の機能（チャンネルフェーダー・ヘッドホンのCUEボタン・テンポフェーダーの向きなど）では試していません。試し直すまでは、ほかの機種と同じく未確認（⚠）として扱います）、AlphaTheta DDJ-FLX2（公式MIDIメッセージ一覧に基づく設定。実機動作は未確認）
- **そのほかの機種**: HIDでつなぐNI Traktor Kontrolを含め、実機では確かめていません（「プリセット一覧」の⚠）。
- **macOSについて**: 初期のバージョン（2026-10-03）は、テストユーザーがmacOS（REAPER 7.47）で動作を確認しました。その後に追加した機能（デッキB・映像の重ね方・HIDの橋渡しなど）はmacOSでは未確認です。Linuxでは試していません。不具合が発生した場合は配布元までお知らせください。

---

## ライセンスとクレジット

ReaScratchはGPL-3.0-or-laterのフリーソフトウェアです（`LICENSE`）。一部に、ほかのライセンスのコードを移して使っています: DJフィルター（Saike FM Filter 2、MITライセンス、`Effects/ReaScratch/LICENSE_Saike_filters.txt`）、VHSの映像（zhuker/ntsc、Apache License 2.0、`Effects/ReaScratch/LICENSE_ntsc_zhuker.txt`）、曲のキーの判定（libKeyFinder、GPL-3.0-or-later）、オートゲインの音の大きさの測り方（libebur128、Jan Kokemüller、MITライセンス、https://github.com/jiixyj/libebur128 ）。K-weightingのフィルターの定数とゲートを、libebur128のとおりにLuaで書いています。HIDの橋渡しのexeに入っている部品のライセンスは`HID bridge/THIRD_PARTY_LICENSES.txt`です。参考にした資料と謝辞は`CREDITS.md`（英語）にあります。
