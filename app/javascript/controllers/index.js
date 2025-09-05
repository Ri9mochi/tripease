// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

// これで app/javascript/controllers 配下の *_controller.js を自動登録
eagerLoadControllersFrom("controllers", application)

// 手動登録が必要な場合は同じ application を使う
import DestinationFilterController from "./destination_filter_controller"
application.register("destination-filter", DestinationFilterController)