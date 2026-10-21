# Chrome Bookmark Launcher

Chrome のブックマークをスマホから素早く開くためのランチャーアプリ（Flutter / iOS・Android・Web 対応）。

Chrome 拡張機能でブックマークをサーバーへ同期し、本アプリからブックマークツリーの閲覧・
お気に入り登録・使用頻度順での一覧・検索・タップでの起動ができます。
**本リポジトリは Flutter アプリ（クライアント）のみを含みます。** Chrome 拡張機能・同期サーバーは別リポジトリです。

## 主な機能

- ブックマークツリーの階層表示
- お気に入り（★）登録・一覧
- 使用頻度順（frecency: 半減期30日の指数減衰）での一覧（頻度バー付き）
- タイトル・URL に対する AND 部分一致検索
- タップで URL を開く（Chrome アプリを優先的に起動）
- オフライン動作（ローカルキャッシュ + 未送信操作の保留キュー）
- ホスト名から決定論的に色付けされるファビコン表示（favicon 取得 OFF でも一覧が色分けされる）
- ライト/ダーク/システムの表示モード切り替え
- 未ペアリング時のペアリング手順ガイド（Chrome 拡張機能の導入〜QR 読み取りまでの画面付き案内）
- ペアリング解除（サーバー側の device_token も失効させ、端末ローカルのみ消去ではない）

## アーキテクチャの要点

- 状態管理: [Riverpod](https://riverpod.dev/) 2.x
- ブックマーク状態は「確定層（サーバーから同期済み）」と「保留層（未送信の操作）」を重ね合わせた
  オーバーレイ方式で保持し、オフライン操作を即座に UI に反映しつつサーバー同期後に確定させる
- ブックマークツリーの解析は `Isolate.run` でメインスレッドをブロックしないように実行
- デザイントークン（`lib/core/design_tokens.dart`・`theme.dart`）でブランドカラー・寸法・
  モーションを一元管理。`ThemeExtension` は明暗で値が変わる意味色のみに限定して使用

## 開発コマンド

```bash
flutter pub get      # 依存パッケージ取得
flutter run           # デバッグ実行（接続デバイス/エミュレータ）
flutter build apk    # Android APK ビルド
flutter build ios    # iOS ビルド（macOS のみ）
flutter test         # テスト実行

# アプリアイコン／スプラッシュの再生成（assets/icon/・assets/branding/ の元画像から）
python3 tool/gen_icon.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create

# ペアリング手順ガイド画像の再生成（tool/guide_raw/ に実機スクショを置いてから実行）
python3 tool/gen_guide_images.py
```

## 注意

- 雛形は `flutter create` で生成されています。
- リリースビルドはデフォルトで**デバッグ鍵署名**です。手元検証用であり、そのまま配布はできません。
- `DELETE /api/v1/device`（ペアリング解除時のサーバー側失効）はサーバー側で実装済み（`204`成功・
  冪等）。未デプロイ環境に向けた場合は 404 を受けてローカルのみ消去するフォールバックに落ちる。
