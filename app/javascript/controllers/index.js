// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

import { Application } from "@hotwired/stimulus"
import DestinationFilterController from "./destination_filter_controller"

window.Stimulus = Application.start()
Stimulus.register("destination-filter", DestinationFilterController)