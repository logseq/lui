(ns components.extensions
  (:require [lui.elements :as elements :refer [defextension]]
            [lui.extension :as ext]
            [lui.macros :refer [defui host]]
            [lui.protocol :as proto :refer [SwiftUIHost WebHost]]))

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

(defn simulator-map-marker-schema []
  (ext/component
   "simulator-map-marker"
   [(proto/profile proto/WebOS proto/WebHost)]
   false []
   [(ext/property "title" ext/StringScalar true None)
    (ext/property "latitude" ext/FloatScalar true None)
    (ext/property "longitude" ext/FloatScalar true None)]
   []))

(defn simulator-map-schema []
  (ext/component
   "simulator-map"
   [(proto/profile proto/WebOS proto/WebHost)]
   false ["simulator-map-marker"]
   [(ext/property "label" ext/StringScalar true None)
    (ext/property "latitude" ext/FloatScalar true None)
    (ext/property "longitude" ext/FloatScalar true None)
    (ext/property "latitude-delta" ext/FloatScalar true None)
    (ext/property "longitude-delta" ext/FloatScalar true None)]
   [(ext/event
     "region-change"
     [(ext/event-field "latitude" ext/FloatScalar true)
      (ext/event-field "longitude" ext/FloatScalar true)
      (ext/event-field "latitude-delta" ext/FloatScalar true)
      (ext/event-field "longitude-delta" ext/FloatScalar true)])]))

(defn simulator-camera-schema []
  (ext/component
   "simulator-camera"
   [(proto/profile proto/WebOS proto/WebHost)]
   false []
   [(ext/property "label" ext/StringScalar true None)
    (ext/property "facing" ext/StringScalar true None)]
   [(ext/event
     "state-change"
     [(ext/event-field "state" ext/StringScalar true)])]))

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

(defn gallery-accent-schema []
  (ext/tweak
   "gallery-accent"
   [(proto/profile proto/WebOS proto/WebHost)
    (proto/profile proto/IOS proto/SwiftUIHost)
    (proto/profile proto/MacOS proto/SwiftUIHost)
    (proto/profile proto/MacOS proto/FlutterHost)
    (proto/profile proto/IOS proto/FlutterHost)
    (proto/profile proto/AndroidOS proto/FlutterHost)
    (proto/profile proto/LinuxOS proto/FlutterHost)
    (proto/profile proto/WindowsOS proto/FlutterHost)]
   []))

(defn registry []
  (let [result (ext/registry)]
    (ext/register-component! result (apple-map-schema))
    (ext/register-component! result (apple-map-marker-schema))
    (ext/register-component! result (simulator-map-schema))
    (ext/register-component! result (simulator-map-marker-schema))
    (ext/register-component! result (simulator-camera-schema))
    (ext/register-component! result (native-card-schema))
    (ext/register-tweak! result (gallery-accent-schema))
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

(defextension simulator-map
  {:identifier "simulator-map"
   :properties
   {:label :string
    :latitude :float
    :longitude :float
    :latitude-delta :float
    :longitude-delta :float}
   :events {:region-change :on-region-change}})

(defextension simulator-map-marker
  {:identifier "simulator-map-marker"
   :properties {:title :string :latitude :float :longitude :float}})

(defextension simulator-camera
  {:identifier "simulator-camera"
   :properties {:label :string :facing :string}
   :events {:state-change :on-state-change}})

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
    WebHost
    (elements/element
     ui-context nil
     [:column {:gap 16}
      [:label "Map"]
      [:components.extensions/simulator-map
       {:label "Map of San Francisco"
        :latitude 37.7793
        :longitude -122.4193
        :latitude-delta 0.08
        :longitude-delta 0.08
        :on-region-change (fn [_event] true)}
       [:components.extensions/simulator-map-marker
        {:title "San Francisco"
         :latitude 37.7793
         :longitude -122.4193}]]
      [:label "Camera"]
      [:components.extensions/simulator-camera
       {:label "Back camera preview"
        :facing "environment"
        :on-state-change (fn [_event] true)}]])
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
    {:ios [:gallery-accent]
     :macos [:gallery-accent]
     :android [:gallery-accent]
     :web [:gallery-accent]}
    "The host factory owns native interaction while LUI retains the node."]])
