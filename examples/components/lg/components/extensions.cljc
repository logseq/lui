(ns components.extensions
  (:require [lui.elements :as elements :refer [defextension]]
            [lui.extension :as ext]
            [lui.macros :refer [defui host]]
            [lui.protocol :as proto :refer [SwiftUIHost]]))

(defn apple-map-marker-schema []
  (ext/component
   "apple-map-marker"
   [(proto/profile proto/IOS proto/SwiftUIHost)
    (proto/profile proto/MacOS proto/SwiftUIHost)]
   false []
   [(ext/property "title" ext/StringScalar true None)
    (ext/property "latitude" ext/FloatScalar true None)
    (ext/property "longitude" ext/FloatScalar true None)]
   []))

(defn apple-map-schema []
  (ext/component
   "apple-map"
   [(proto/profile proto/IOS proto/SwiftUIHost)
    (proto/profile proto/MacOS proto/SwiftUIHost)]
   false ["apple-map-marker"]
   [(ext/property "latitude" ext/FloatScalar true None)
    (ext/property "longitude" ext/FloatScalar true None)
    (ext/property "latitude-delta" ext/FloatScalar true None)
    (ext/property "longitude-delta" ext/FloatScalar true None)]
   []))

(defn native-card-schema []
  (ext/component
   "native-card"
   [(proto/profile proto/WebOS proto/WebHost)
    (proto/profile proto/MacOS proto/FlutterHost)
    (proto/profile proto/IOS proto/FlutterHost)
    (proto/profile proto/AndroidOS proto/FlutterHost)
    (proto/profile proto/LinuxOS proto/FlutterHost)
    (proto/profile proto/WindowsOS proto/FlutterHost)]
   false []
   [(ext/property "title" ext/StringScalar true None)]
   []))

(defn registry []
  (let [result (ext/registry)]
    (ext/register-component! result (apple-map-schema))
    (ext/register-component! result (apple-map-marker-schema))
    (ext/register-component! result (native-card-schema))
    result))

(defextension apple-map
  {:identifier "apple-map"
   :properties
   {:latitude :float
    :longitude :float
    :latitude-delta :float
    :longitude-delta :float}})

(defextension apple-map-marker
  {:identifier "apple-map-marker"
   :properties {:title :string :latitude :float :longitude :float}})

(defextension native-card
  {:identifier "native-card"
   :properties {:title :string}})

(defui native-extension-content []
  (match (host)
    SwiftUIHost
    (elements/element
     ui-context nil
     [:components.extensions/apple-map
      {:latitude 37.7793
       :longitude -122.4193
       :latitude-delta 0.08
       :longitude-delta 0.08}
      [:components.extensions/apple-map-marker
       {:title "San Francisco"
        :latitude 37.7793
        :longitude -122.4193}]])
    _
    (elements/element
     ui-context nil
     [:components.extensions/native-card
      {:title "Native retained state"}])))

(defui native-extension-gallery []
  [:column {:gap 12 :padding 16}
   [:heading {:level 2} "NativeExtension"]
   [native-extension-content]
   [:paragraph
    "The host factory owns native interaction while LUI retains the node."]])
