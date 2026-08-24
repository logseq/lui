(ns lui.host.ctypes
  (:require [ocaml.package/ctypes]
            [ocaml.package/ctypes.foreign]
            [ocaml.Ctypes :as ctypes :refer [string int void]]
            [ocaml.Foreign :as foreign]
            [ocaml.Dl :as dl]))

(def ^:Ctypes.typ<string> c-string string)
(def ^:Ctypes.typ<int> c-int int)
(def ^:Ctypes.typ<unit> c-void void)

(defn open-library [path]
  (dl/dlopen :filename path :flags (list (dl/RTLD_NOW))))

(defn bind-string-int [library symbol]
  (foreign/foreign
   symbol
   (ctypes/@-> c-string (ctypes/returning c-int))
   :from library))

(defn bind-int-int [library symbol]
  (foreign/foreign
   symbol
   (ctypes/@-> c-int (ctypes/returning c-int))
   :from library))

(defn bind-unit-unit [library symbol]
  (foreign/foreign
   symbol
   (ctypes/@-> c-void (ctypes/returning c-void))
   :from library))

(defn bind-event-setter [library symbol]
  (let [event-type
        (ctypes/@->
         c-int
         (ctypes/@->
          c-int
          (ctypes/@-> c-string (ctypes/returning c-void))))
        callback-type (foreign/funptr event-type)]
    (foreign/foreign
     symbol
     (ctypes/@-> callback-type (ctypes/returning c-void))
     :from library)))
