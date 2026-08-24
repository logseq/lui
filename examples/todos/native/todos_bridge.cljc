(ns todos.flutter-bridge
  (:require [lui.protocol :as proto]
            [lui.app :as driver]
            [lui.backend.flutter :as flutter]
            [todos.app :as todos]
            [ocaml.Callback :as callback]))

(def latest-patch (atom ""))
(def current-app (atom None))

(defn send-patch! [json]
  (reset! latest-patch json)
  true)

(defn operating-system [platform-code]
  (match platform-code
    1 proto/MacOS
    2 proto/IOS
    3 proto/AndroidOS
    4 proto/LinuxOS
    5 proto/WindowsOS
    _ proto/GenericOS))

(defn app []
  (match (deref current-app)
    (Some value) value
    None (raise (Invalid_argument "Flutter Todos bridge is not started"))))

(defn initialize [platform-code]
  (reset! latest-patch "")
  (let [renderer (flutter/create-wire send-patch!)
        value
        (todos/create
         (flutter/backend-for renderer (operating-system platform-code)))]
    (reset! current-app (Some value))
    (driver/start! value)
    (driver/flush! value)
    (deref latest-patch)))

(defn press [node]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/Press node))
  (driver/flush! (app))
  (deref latest-patch))

(defn hold [node]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/Hold node))
  (driver/flush! (app))
  (deref latest-patch))

(defn text-changed [node text]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/TextChanged node text))
  (driver/flush! (app))
  (deref latest-patch))

(defn toggle-changed [node checked]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/ToggleChanged node checked))
  (driver/flush! (app))
  (deref latest-patch))

(defn dispose []
  (reset! latest-patch "")
  (driver/dispose! (app))
  (deref latest-patch))

(defn root-node [] (driver/root-node (app)))

(callback/register "lui_flutter_init" initialize)
(callback/register "lui_flutter_press" press)
(callback/register "lui_flutter_hold" hold)
(callback/register "lui_flutter_text_changed" text-changed)
(callback/register "lui_flutter_toggle_changed" toggle-changed)
(callback/register "lui_flutter_dispose" dispose)
(callback/register "lui_flutter_root_node" root-node)
