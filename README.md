## アプリケーション名
Tripease

## アプリケーション概要
旅行の計画をAIが自動でプランニングを行い、登録した旅行プランはマイページ上で管理することができる。

## URL
https://tripease-8qia.onrender.com

## テスト用アカウント
・Basic認証ID：admin
・Basic認証パスワード：test1234
・メールアドレス：test3@test.co.jp
・パスワード：test1234

## 利用方法
### AI自動プラン機能
・「新しい旅行を計画する」をクリックし、検索条件を入力するとAIが自動で旅行プランを2案作成してくれます。
・提案された旅行プランをクリックするとプランの詳細をプレビューできます。
・気に入ったプランがあれば登録をすることができます。

### 登録プランの管理
・登録されたプランはマイページ上に登録をされます。
・登録されたプランの詳細をマイページ上で確認することができます。

## アプリケーションを作成した背景
旅行に行くのは好きだが、旅行を計画し、手配をする煩わしさを感じていた自身の実体験から、
旅行計画等の準備の手間を省くことで、旅行に行くハードルを下げたいという思いから、本アプリケーションを作成をしました。

## 洗い出した要件
https://docs.google.com/spreadsheets/d/1IUagI43PD9eNOFz97Y5nwwy7l1HjjJoL/edit?usp=sharing&ouid=110602170881444460436&rtpof=true&sd=true

## 実装した機能についての画像やGIFおよびその説明
[![Image from Gyazo](https://i.gyazo.com/f0cdd0a6b38ff8084c8259d324055951.gif)](https://gyazo.com/f0cdd0a6b38ff8084c8259d324055951)
[![Image from Gyazo](https://i.gyazo.com/3e0bf2181f15c83101bac8e7004c74ca.gif)](https://gyazo.com/3e0bf2181f15c83101bac8e7004c74ca)
[![Image from Gyazo](https://i.gyazo.com/98c5a16a04a816718cedfe4f98a3a0b5.gif)](https://gyazo.com/98c5a16a04a816718cedfe4f98a3a0b5)
[![Image from Gyazo](https://i.gyazo.com/57f8b4389b81d0ad61a4ed7e7b6eb157.gif)](https://gyazo.com/57f8b4389b81d0ad61a4ed7e7b6eb157)

## 実装予定の機能
・プレビューされたプランの編集機能。（現在実装中）
・AI機能の高度化
・DB最適化

## データベース設計
[![Image from Gyazo](https://i.gyazo.com/ca99a5f77870e4bf5f8ac83f24133eaf.png)](https://gyazo.com/ca99a5f77870e4bf5f8ac83f24133eaf)

## 画面遷移図
[![Image from Gyazo](https://i.gyazo.com/9c9d52ffa8848082e2587784e4f888cf.png)](https://gyazo.com/9c9d52ffa8848082e2587784e4f888cf)

## 開発環境
・フロントエンド
  - HTML, CSS, JavaScript
・バックエンド
  - Ruby, Ruby on Rails
・データベース
  - PostgreSQL
・テスト
  - RSpec
・API
  - GeminiAPI
・テキストエディタ
  - Visual Studio Code
・バージョン管理
  - GitHub

## 工夫したポイント
AIから出力されるデータを所定のビューで反映されるようにコントローラーの設定を行っている点。
また、食事どころのURLはすべて食べログが出力され、AIの提示内容とURLが一致するようプロンプトを設定している点。