# AccountPicker

**リンクをクリックするたびに「どのGoogleアカウント(Chromeプロファイル)で開くか」を選べる、macOS用の無料ツールです。**

[English README → README.md](README.md)

SlackやChatworkでGoogleドキュメントのリンクを踏んだとき、意図しないアカウントで開いてしまい閲覧履歴（足跡）が残る——それを防ぎます。

## 特徴

- リンクをクリックすると選択ダイアログが出て、選んだChromeプロファイルで開く
- **Chromeのプロファイル一覧を毎回自動取得**。アカウントの追加・削除・名前変更はすべて自動反映、設定ファイルの編集は不要
- シークレットウィンドウ（足跡を残さない）も選択肢に常時表示
- **完全無料・完全ローカル動作**。ネットワーク通信ゼロ、履歴やアカウント情報の送信・収集は一切なし（ソースはこのリポジトリの1ファイルだけなので、誰でも中身を確認できます）
- 追加アプリ・有料ソフト不要。macOS標準機能（AppleScript）だけで動作

## 必要なもの

- macOS（Apple Silicon / Intel どちらも可）
- Google Chrome

## インストール

1. `install.sh` をダウンロード
2. ターミナルを開いて実行:

```bash
bash ~/Downloads/install.sh
```

3. 画面の質問に答える（動作テスト → デフォルトブラウザ設定。macOSの確認ダイアログが出たら「"AccountPicker"を使用」をクリック）

以上です。以後、あらゆるアプリでリンクをクリックすると選択ダイアログが表示されます。

## 使い方のヒント

- 選択肢はChromeの現在のプロファイルがそのまま並びます（Chrome上の名前＋ログイン中のメールアドレス）
- ダブルクリックまたは選択してReturnで開く、escでキャンセル
- アプリのアイコン（`~/Applications/AccountPicker.app`）をダブルクリックすると、動作テストやプロファイル一覧の確認ができます

## 調子が悪いとき

```bash
bash install.sh --doctor
```

登録状態・デフォルトブラウザ・Chromeプロファイルを一括診断します。

## アンインストール

```bash
bash install.sh --uninstall
```

デフォルトブラウザを元（Chrome/Safari）に戻し、アプリを削除します。

## 仕組み（技術的な説明）

`install.sh` がAppleScriptアプレットをその場でコンパイルし、`Info.plist` に http/https スキームとHTML書類の宣言を追加して、macOSに「ブラウザ」として登録します。デフォルトブラウザに設定すると、OSからURLが `on open location` ハンドラに渡され、ChromeのLocal State（プロファイル情報）を読んで選択ダイアログを構築し、選択結果を `open -na "Google Chrome" --args --profile-directory="..."` で起動します。

## 注意事項

- Slack/Chatwork等のデスクトップアプリが「アプリ内ブラウザで開く」設定の場合はOSのデフォルトブラウザを経由しません。各アプリの設定で「外部ブラウザで開く」にしてください
- 1つのChromeプロファイルに複数のGoogleアカウントがログインしていると、Google側の仕様で既定アカウントが使われます。「1プロファイル=1アカウント」での運用を推奨します
- 本ソフトウェアは無保証です（MIT License）。自己責任でご利用ください

## License

MIT
