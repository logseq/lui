(ns components.flutter-bridge
  (:require [lui.protocol :as proto]
            [lui.app :as driver]
            [lui.backend.flutter :as flutter]
            [components.app :as components]
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
    None (raise (Invalid_argument "Flutter component bridge is not started"))))

(defn initialize [platform-code]
  (reset! latest-patch "")
  (let [renderer (flutter/create-wire send-patch!)
        value
        (components/create
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

(defn submit [node]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/Submit node))
  (driver/flush! (app))
  (deref latest-patch))

(defn dismiss [node]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/Dismiss node))
  (driver/flush! (app))
  (deref latest-patch))

(defn toggle-changed [node checked]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/ToggleChanged node checked))
  (driver/flush! (app))
  (deref latest-patch))

(defn radio-changed [node]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/Change node))
  (driver/flush! (app))
  (deref latest-patch))

(defn slider-changed [node value]
  (reset! latest-patch "")
  (driver/dispatch-event! (app) (proto/ValueChanged node value))
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
(callback/register "lui_flutter_submit" submit)
(callback/register "lui_flutter_dismiss" dismiss)
(callback/register "lui_flutter_toggle_changed" toggle-changed)
(callback/register "lui_flutter_radio_changed" radio-changed)
(callback/register "lui_flutter_slider_changed" slider-changed)
(callback/register "lui_flutter_dispose" dispose)
(callback/register "lui_flutter_root_node" root-node)
