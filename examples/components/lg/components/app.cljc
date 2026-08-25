(ns components.app
  (:require [signal.core]
            [lui.app :as app]
            [components.model :as model]
            [components.view :as view]))

(defn create [backend]
  (app/create backend (model/initial) model/update view/gallery-view))

(defn create-with-extensions [backend registry]
  (app/create-with-extensions
   backend registry (model/initial) model/update
   view/gallery-view-with-extensions))

(defn model [application]
  (app/model application))
