(ns lui.apple-bridge-test
  (:require [clojure.test :refer [deftest is]]
            [lui.protocol :refer [Press]]
            [lui.runtime :as runtime]
            [lui.app :as driver]
            [lui.backend.apple :as renderer]
            [lui.host.apple :as apple]
            [todos.app :as todos]
            [ocaml.Sys :as sys]))

(deftest lg-calls-the-swift-appkit-host
  (let [events (atom [])
        host
        (apple/connect
         (sys/getenv "LUI_APPLE_LIBRARY")
         (fn [event]
           (swap! events conj event)
           (print "")))]
    (apple/reset-host! host)
    (is
     (apple/apply-json!
      host
      "{\"generation\":1,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"row\"},{\"op\":\"create-node\",\"id\":2,\"kind\":\"text\"},{\"op\":\"create-node\",\"id\":3,\"kind\":\"button\"},{\"op\":\"set-prop\",\"id\":2,\"property\":\"text\",\"value\":\"LG to Swift\"},{\"op\":\"set-prop\",\"id\":3,\"property\":\"text\",\"value\":\"Continue\"},{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0},{\"op\":\"insert-child\",\"parent\":1,\"child\":3,\"index\":1}]}"))
    (is
     (not
      (apple/apply-json!
       host
       "{\"generation\":2,\"ops\":[{\"op\":\"insert-child\",\"parent\":99,\"child\":2,\"index\":0}]}")))
    (is (apple/perform-action! host 3))
    (is (= 1 (count @events)))
    (match (nth @events 0)
      (Press node) (is (= 3 node))
      _ (is false "Swift returns a typed press event"))
    (apple/reset-host! host)))

(deftest declarative-lg-todos-round-trips-through-appkit
  (let [events (atom [])
        host
        (apple/connect
         (sys/getenv "LUI_APPLE_LIBRARY")
         (fn [event]
           (swap! events conj event)
           (print "")))
        backend
        (renderer/create-wire
         (fn [json] (apple/apply-json! host json)))
        application (todos/create (renderer/backend backend))]
    (apple/reset-host! host)
    (driver/start! application)
    (driver/flush! application)
    (let [runtime-app (driver/runtime application)
          root-children
          (runtime/children runtime-app (driver/root-node application))
          controls (nth root-children 1)
          input (nth (runtime/children runtime-app controls) 0)
          add (nth (runtime/children runtime-app controls) 1)]
      (driver/dispatch-event!
       application (lui.protocol/TextChanged input "AppKit Todo"))
      (driver/flush! application)
      (is (= "AppKit Todo" (:model-draft (todos/model application))))
      (is (apple/perform-action! host add))
      (driver/dispatch-event! application (nth (deref events) 0))
      (driver/flush! application)
      (is (= 1 (count (:model-items (todos/model application)))))
      (is (= "AppKit Todo"
             (:todo-title
              (nth (:model-items (todos/model application)) 0))))
      (is (= "" (:model-draft (todos/model application)))))
    (apple/reset-host! host)))
