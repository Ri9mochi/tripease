// app/javascript/controllers/index.js

import { application } from "./application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

// eagerLoadControllersFrom("controllers", application)をコメントアウトまたは削除し、
// Stimulusコントローラーをまとめて読み込むように修正します。

// Stimulusコントローラーを自動的に読み込む
eagerLoadControllersFrom("controllers", application)