import { Application } from "@hotwired/stimulus"
import DestinationFilterController from "./destination_filter_controller"

window.Stimulus = Application.start()
Stimulus.register("destination-filter", DestinationFilterController)