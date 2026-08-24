(ns components.app-test
  (:require [clojure.test :refer [deftest is]]
            [lui.app :as driver]
            [lui.backend.flutter :as flutter]
            [components.app :as components]
            [components.model :as model]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(deftest gallery-model-owns-the-shared-showcase-state
  (let [initial (model/initial)
        advanced (model/update initial model/AdvanceProgress)
        wrapped
        (model/update
         (record model/gallery-model
                 (gallery-disabled false)
                 (gallery-field-value "")
                 (gallery-checked false)
                 (gallery-progress 1.0)
                 (gallery-density "comfortable")
                 (gallery-volume 0.35))
         model/AdvanceProgress)]
    (assert-equal false (:gallery-disabled initial) "controls start enabled")
    (assert-equal 0.3 (:gallery-progress initial) "progress has a visible start")
    (assert-equal "comfortable" (:gallery-density initial)
                  "radio group starts with a visible selection")
    (assert-equal 0.35 (:gallery-volume initial)
                  "slider starts with a fractional shared value")
    (assert-equal 0.4 (:gallery-progress advanced) "progress advances by a tenth")
    (assert-equal 0.0 (:gallery-progress wrapped) "progress wraps after completion")
    (assert-equal
     "draft@example.com"
     (:gallery-field-value
      (model/update initial (model/SetFieldValue "draft@example.com")))
     "text input state is shared across every host")
    (assert-equal
     "compact"
     (:gallery-density (model/update initial (model/SetDensity "compact")))
     "radio selection is owned by the shared reducer")
    (assert-equal
     0.8
     (:gallery-volume (model/update initial (model/SetVolume 0.8)))
     "slider value is owned by the shared reducer")))

(deftest native-gallery-app-batches-actions-and-disposes-the-retained-tree
  (let [renderer (flutter/create)
        application (components/create (flutter/backend renderer))]
    (driver/start! application)
    (driver/flush! application)
    (is (> (flutter/node-count renderer) 30)
        "the native gallery mounts the complete shared component source")
    (assert-equal 1 (count (flutter/batches renderer)) "mount is one batch")
    (let [mounted-count (flutter/node-count renderer)]
      (driver/send! application model/ToggleDisabled)
      (driver/flush! application)
      (assert-equal
       (inc mounted-count) (flutter/node-count renderer)
       "a shared Signal action mounts only the conditional status node"))
    (assert-equal
     true
     (:gallery-disabled (components/model application))
     "the shared reducer owns disabled state")
    (driver/send! application (model/SetChecked true))
    (driver/flush! application)
    (assert-equal
     true
     (:gallery-checked (components/model application))
     "toggle state is shared across hosts")
    (driver/dispose! application)
    (assert-equal 0 (flutter/node-count renderer) "dispose drops every retained node")
    (is (driver/disposed? application) "the native gallery lifecycle terminates")))
