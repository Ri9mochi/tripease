// app/javascript/controllers/index.js

// import { application } from "./application" は不要
// 代わりに@hotwired/stimulus-loadingからインポート
import { Application } from "@hotwired/stimulus"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

// Stimulusアプリケーションを初期化
const application = Application.start()

// controllersディレクトリ内の全てのコントローラーを自動的に読み込む
eagerLoadControllersFrom("controllers", application)