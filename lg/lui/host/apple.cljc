(ns lui.host.apple
  (:require [lui.protocol :as proto]
            [lui.host.ctypes :as native]))

(defn connect [library-path on-event]
  (let [library (native/open-library library-path)
        apply-json (native/bind-string-int library "lui_apple_apply")
        show-window (native/bind-unit-unit library "lui_apple_show")
        reset-host (native/bind-unit-unit library "lui_apple_reset")
        perform-action
        (native/bind-int-int library "lui_apple_perform_action")
        set-event-callback
        (native/bind-event-setter library "lui_apple_set_event_callback")
        callback
        (fn [kind]
          (fn [node]
            (fn [text]
              (if (= kind 0)
                (on-event (proto/Press node))
                (on-event (proto/TextChanged node text))))))]
    (set-event-callback callback)
    (record apple-host
      (apple-apply-json apply-json)
      (apple-show-window show-window)
      (apple-reset-host reset-host)
      (apple-perform-action perform-action)
      (apple-event-callback callback))))

(defn apply-json! [host json]
  (= 1 ((:apple-apply-json host) json)))

(defn show! [host]
  ((:apple-show-window host)))

(defn reset-host! [host]
  ((:apple-reset-host host)))

(defn perform-action! [host node]
  (= 1 ((:apple-perform-action host) node)))
