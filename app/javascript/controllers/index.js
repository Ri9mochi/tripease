// app/javascript/controllers/index.js

import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

eagerLoadControllersFrom("controllers", application)

import DestinationFilterController from "./destination_filter_controller.js"
application.register("destination-filter", DestinationFilterController)