(ns components.app
  (:require [signal.core]
            [lui.app :as app]
            [components.model :as model]
            [components.view :as view]))

(defn create [backend]
  (app/create-reloadable
   backend "components-gallery" "components-gallery-v1"
   (model/initial) model/update view/gallery-view))

(defn create-with-extensions [backend registry]
  (app/create-reloadable-with-extensions
   backend registry "components-gallery" "components-gallery-v1"
   (model/initial) model/update
   view/gallery-view-with-extensions))

(defn model [application]
  ((.-app-read-model application) nil))
