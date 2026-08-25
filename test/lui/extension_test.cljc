(ns lui.extension-test
  (:require [clojure.test :refer [deftest is]]
            [signal.core :as sig]
            [lui.protocol :as proto]
            [lui.extension :as ext]
            [lui.runtime :as runtime]
            [lui.ui :as ui]
            [lui.elements :refer [defextension]]
            [lui.macros :refer [defui]]
            [lui.backend.retained :as retained]
            [lui.backend.apple :as apple]
            [lui.backend.flutter :as flutter]
            [lui.wire :as wire]))

(defextension native-view
  {:identifier "native-view"
   :properties {:title :string}
   :events {:activate :on-activate}})

(defui native-view-example [title-source on-activate]
  [:column
   [:lui.extension-test/native-view
    {:title title-source :on-activate on-activate}]])

(defui platform-tweak-example []
  [:button
   {:ios [[:glass-card {:prominent true}]
          :glass-card]}
   "Save"])

(defui tweaked-tab-example []
  [:tabs
   [:button {:ios [:glass-card] :selected true} "Overview"]])

(defui reactive-platform-tweak-example [prominent]
  [:button
   {:ios [[:glass-card {:prominent prominent}]]}
   "Save"])

(defmacro recording-backend [profile batches]
  `(record proto/backend
     (backend-profile ~profile)
     (apply-batch
      (fn [batch]
        (swap! ~batches conj batch)
        true))))

(defn marker-schema []
  (ext/component
   "map-marker"
   [(proto/profile proto/IOS proto/SwiftUIHost)]
   false
   []
   [(ext/property "id" ext/StringScalar true None)
    (ext/property "latitude" ext/FloatScalar true None)
    (ext/property "longitude" ext/FloatScalar true None)]
   []))

(defn map-schema []
  (ext/component
   "map"
   [(proto/profile proto/IOS proto/SwiftUIHost)]
   false
   ["map-marker"]
   [(ext/property "latitude" ext/FloatScalar true None)
    (ext/property "longitude" ext/FloatScalar true None)
    (ext/property
     "shows-user-location" ext/BoolScalar false
     (Some (proto/BoolValue false)))]
   [(ext/event
     "region-change"
     [(ext/event-field "latitude" ext/FloatScalar true)
      (ext/event-field "longitude" ext/FloatScalar true)])]))

(defn ios-registry []
  (let [registry (ext/registry)]
    (ext/register-component! registry (map-schema))
    (ext/register-component! registry (marker-schema))
    registry))

(defn flutter-schema []
  (ext/component
   "native-view"
   [(proto/profile proto/AndroidOS proto/FlutterHost)]
   false []
   [(ext/property "title" ext/StringScalar true None)]
   [(ext/event "activate" [])]))

(defn ios-tweak-schema []
  (ext/tweak
   "glass-card"
   [(proto/profile proto/IOS proto/SwiftUIHost)]
   [(ext/property "prominent" ext/BoolScalar false
                  (Some (proto/BoolValue false)))]))

(defn runtime-extension-property [application node property]
  (match (clojure.core/get
          (deref (:runtime-extension-properties application)) node)
    (Some properties) (clojure.core/get properties property)
    None None))

(deftest component-schema-has-a-deterministic-fingerprint
  (is (= (ext/fingerprint (map-schema))
         (ext/fingerprint (map-schema)))
      "the same manifest has the same fingerprint")
  (is (not (= (ext/fingerprint (map-schema))
              (ext/fingerprint (marker-schema))))
      "different manifests cannot share a fingerprint"))

(deftest tweak-schemas-share-the-registry-with-a-distinct-identity
  (let [registry (ext/registry)
        schema (ios-tweak-schema)]
    (ext/register-tweak! registry schema)
    (is (ext/tweak? registry "glass-card"))
    (is (= (Some schema) (ext/schema registry "glass-card")))
    (is (not (= (ext/tweak-fingerprint schema) (ext/fingerprint schema))))
    (is (thrown?
         Invalid_argument
         (ext/register-component! registry schema))
        "a tweak and component cannot reuse one identifier")))

(deftest registry-validates-identities-and-freezes-at-startup
  (let [registry (ext/registry)]
    (ext/register-component! registry (map-schema))
    (ext/register-component! registry (marker-schema))
    (is (= (Some (map-schema)) (ext/schema registry "map"))
        "registered schemas remain application-local")
    (is (ext/freeze! registry) "a complete registry freezes")
    (is (ext/frozen? registry) "freeze state is observable")
    (is (thrown? Invalid_argument
                 (ext/register-component! registry (marker-schema)))
        "registration is immutable after startup"))
  (doseq [identifier ["" "Map" "map_marker" "-map" "map-"]]
    (is (thrown?
         Invalid_argument
         (ext/register-component!
          (ext/registry)
          (ext/component identifier [] false [] [] [])))
        "extension identifiers use non-empty kebab-case"))
  (is (thrown?
       Invalid_argument
       (ext/register-component!
        (ext/registry)
        (ext/component "button" [] false [] [] [])))
      "an extension cannot shadow a standard element"))

(deftest registry-rejects-duplicate-and-incomplete-schemas
  (let [registry (ext/registry)]
    (ext/register-component! registry (map-schema))
    (is (thrown? Invalid_argument
                 (ext/register-component! registry (map-schema)))
        "an identifier can be registered only once")
    (is (thrown? Invalid_argument (ext/freeze! registry))
        "referenced extension child schemas must exist")
    (is (not (ext/frozen? registry))
        "a failed freeze leaves the registry mutable"))
  (is (thrown?
       Invalid_argument
       (ext/component
        "invalid-default" [] false []
        [(ext/property
          "count" ext/IntScalar false (Some (proto/StringValue "one")))]
        []))
      "property defaults use their declared scalar type")
  (is (thrown?
       Invalid_argument
       (ext/component
        "duplicate-property" [] false []
        [(ext/property "title" ext/StringScalar false None)
         (ext/property "title" ext/StringScalar false None)]
        []))
      "schema property names are unique")
  (is (thrown?
       Invalid_argument
       (ext/component
        "duplicate-child" [] false ["map-marker" "map-marker"] [] []))
      "schema child identifiers are unique"))

(deftest schema-validates-profile-properties-and-event-payloads
  (let [schema (map-schema)]
    (is (ext/profile-supported?
         schema (proto/profile proto/IOS proto/SwiftUIHost)))
    (is (not (ext/profile-supported?
              schema (proto/profile proto/MacOS proto/SwiftUIHost))))
    (is (ext/property-value-supported?
         schema "latitude" (proto/FloatValue 37.3)))
    (is (not (ext/property-value-supported?
              schema "latitude" (proto/IntValue 37))))
    (is (ext/event-payload-supported?
         schema "region-change"
         {"latitude" (proto/FloatValue 37.3)
          "longitude" (proto/FloatValue -122.0)}))
    (is (not (ext/event-payload-supported?
              schema "region-change"
              {"latitude" (proto/FloatValue 37.3)})))
    (is (not (ext/event-payload-supported?
              schema "tap" (hash-map))))))

(deftest extension-patches-have-a-stable-native-wire-format
  (let [batch
        (record proto/patch-batch
          (generation 4)
          (ops
           [(proto/create-extension-op 1 "map" "manifest-v1")
            (proto/set-extension-prop-op
             1 "latitude" (proto/FloatValue 37.3))
            (proto/remove-extension-prop-op 1 "latitude")]))]
    (is
     (=
      (str
       "{\"generation\":4,\"ops\":["
       "{\"op\":\"create-extension\",\"id\":1,"
       "\"identifier\":\"map\",\"fingerprint\":\"manifest-v1\"},"
       "{\"op\":\"set-extension-prop\",\"id\":1,"
       "\"property\":\"latitude\",\"value\":37.3},"
       "{\"op\":\"remove-extension-prop\",\"id\":1,"
       "\"property\":\"latitude\"}]}")
      (wire/encode-batch batch)))))

(deftest runtime-freezes-and-emits-extension-nodes
  (let [registry (ios-registry)
        batches (atom [])
        application
        (runtime/create-with-extensions
         (sig/scheduler)
         (recording-backend
          (proto/profile proto/IOS proto/SwiftUIHost) batches)
         registry)
        map-node (runtime/create-extension-node! application "map")
        marker-node (runtime/create-extension-node! application "map-marker")]
    (is (ext/frozen? registry) "application startup freezes registration")
    (runtime/set-extension-prop!
     application map-node "latitude" (proto/FloatValue 37.3))
    (runtime/set-extension-prop!
     application map-node "longitude" (proto/FloatValue -122.0))
    (runtime/set-extension-prop!
     application marker-node "id" (proto/StringValue "office"))
    (runtime/set-extension-prop!
     application marker-node "latitude" (proto/FloatValue 37.4))
    (runtime/set-extension-prop!
     application marker-node "longitude" (proto/FloatValue -122.1))
    (runtime/insert-child! application map-node marker-node 0)
    (is (runtime/flush! application))
    (is (= 1 (runtime/generation application)))
    (is (= 1 (count (deref batches))))
    (is (= 2 (runtime/mounted-count application))
        "standard and extension nodes share lifecycle accounting")))

(deftest runtime-rejects-invalid-extension-operations-before-a-batch
  (let [registry (ios-registry)
        batches (atom [])
        application
        (runtime/create-with-extensions
         (sig/scheduler)
         (recording-backend
          (proto/profile proto/IOS proto/SwiftUIHost) batches)
         registry)
        map-node (runtime/create-extension-node! application "map")]
    (is (thrown? Invalid_argument
                 (runtime/set-extension-prop!
                  application map-node "latitude" (proto/IntValue 37))))
    (is (thrown? Invalid_argument (runtime/flush! application))
        "a missing required property rejects the whole pending batch")
    (is (= 0 (runtime/generation application)))
    (is (empty? (deref batches)) "the backend sees no partial batch")
    (runtime/set-extension-prop!
     application map-node "latitude" (proto/FloatValue 37.3))
    (runtime/set-extension-prop!
     application map-node "longitude" (proto/FloatValue -122.0))
    (is (runtime/flush! application)
        "the unchanged pending batch can be repaired and retried")))

(deftest runtime-validates-extension-profiles-children-and-events
  (let [registry (ios-registry)
        unsupported
        (runtime/create-with-extensions
         (sig/scheduler)
         (recording-backend
          (proto/profile proto/MacOS proto/SwiftUIHost) (atom []))
         registry)]
    (is (thrown? Invalid_argument
                 (runtime/create-extension-node! unsupported "map"))))
  (let [registry (ios-registry)
        application
        (runtime/create-with-extensions
         (sig/scheduler)
         (recording-backend
          (proto/profile proto/IOS proto/SwiftUIHost) (atom []))
         registry)
        root (runtime/create-node! application proto/Column)
        map-node (runtime/create-extension-node! application "map")
        marker-node (runtime/create-extension-node! application "map-marker")
        text-node (runtime/create-node! application proto/Text)
        scope (sig/scope "extension-events")
        received (atom [])]
    (is (runtime/insert-child! application root map-node 0)
        "general standard containers accept extensions")
    (is (runtime/insert-child! application map-node marker-node 0))
    (is (thrown? Invalid_argument
                 (runtime/insert-child! application map-node text-node 1)))
    (runtime/on-event! scope application map-node
                       (fn [event]
                         (swap! received conj event)
                         true))
    (is (runtime/dispatch!
         application
         (proto/ExtensionEvent
          map-node "map" "region-change"
          {"latitude" (proto/FloatValue 37.3)
           "longitude" (proto/FloatValue -122.0)})))
    (sig/stabilize! (:runtime-scheduler application))
    (is (= 1 (count (deref received))))
    (is (thrown?
         Invalid_argument
         (runtime/dispatch!
          application
          (proto/ExtensionEvent
           map-node "map-marker" "region-change" (hash-map)))))
    (is (thrown?
         Invalid_argument
         (runtime/dispatch!
          application
          (proto/ExtensionEvent
           map-node "map" "region-change"
           {"latitude" (proto/FloatValue 37.3)}))))))

(deftest retained-extension-batches-validate-before-commit
  (let [registry (ios-registry)
        _frozen (ext/freeze! registry)
        store (retained/create-store)
        create-platform (fn [_node _identifier] 42)
        valid
        (record proto/patch-batch
          (generation 1)
          (ops
           [(proto/create-extension-op
             1 "map" (ext/fingerprint (map-schema)))
            (proto/set-extension-prop-op
             1 "latitude" (proto/FloatValue 37.3))
            (proto/set-extension-prop-op
             1 "longitude" (proto/FloatValue -122.0))]))]
    (is (retained/apply-extension-batch!
         store create-platform registry valid))
    (is (= (Some "map") (retained/extension-identifier store 1)))
    (is (= (Some (proto/FloatValue 37.3))
           (retained/extension-property store 1 "latitude")))
    (is (= (Some 42) (retained/platform-node store 1)))
    (let [update
          (record proto/patch-batch
            (generation 2)
            (ops
             [(proto/set-extension-prop-op
               1 "latitude" (proto/FloatValue 38.0))]))]
      (retained/apply-extension-batch! store create-platform registry update)
      (is
       (= (Some 42) (retained/platform-node store 1))
       "property patches preserve the platform object identity"))
    (let [invalid
          (record proto/patch-batch
            (generation 3)
            (ops
             [(proto/create-extension-op 2 "map" "wrong-fingerprint")]))]
      (is (thrown? Invalid_argument
                   (retained/apply-extension-batch!
                    store create-platform registry invalid)))
      (is (= 2 (retained/generation store)))
      (is (= None (retained/node store 2))
          "a rejected extension batch leaves no partial node"))))

(deftest apple-proxy-backend-retains-registered-extensions
  (let [registry (ios-registry)
        renderer (apple/create-with-extensions registry)
        application
        (runtime/create-with-extensions
         (sig/scheduler)
         (apple/backend-for renderer proto/IOS proto/SwiftUIHost)
         registry)
        map-node (runtime/create-extension-node! application "map")]
    (runtime/set-extension-prop!
     application map-node "latitude" (proto/FloatValue 37.3))
    (runtime/set-extension-prop!
     application map-node "longitude" (proto/FloatValue -122.0))
    (runtime/flush! application)
    (is (= (Some (apple/AppleExtension "map"))
           (apple/node renderer map-node)))
    (is (= (Some (proto/FloatValue 37.3))
           (retained/extension-property
            (:apple-store renderer) map-node "latitude")))))

(deftest flutter-proxy-backend-retains-registered-extensions
  (let [registry (ext/registry)
        _registered (ext/register-component! registry (flutter-schema))
        renderer (flutter/create-with-extensions registry)
        application
        (runtime/create-with-extensions
         (sig/scheduler)
         (flutter/backend-for renderer proto/AndroidOS)
         registry)
        node (runtime/create-extension-node! application "native-view")]
    (runtime/set-extension-prop!
     application node "title" (proto/StringValue "Android"))
    (runtime/flush! application)
    (is (= (Some (flutter/FlutterExtension "native-view"))
           (flutter/node renderer node)))))

(deftest defextension-authors-typed-reactive-properties-and-events
  (let [registry (ext/registry)
        _registered (ext/register-component! registry (flutter-schema))
        batches (atom [])
        scheduler (sig/scheduler)
        application
        (runtime/create-with-extensions
         scheduler
         (recording-backend
          (proto/profile proto/AndroidOS proto/FlutterHost) batches)
         registry)
        scope (sig/scope "extension-authoring")
        context (ui/context application scope)
        title (sig/state scheduler "Native title")
        received (atom [])
        root
        (native-view-example
         context
         (sig/value title)
         (fn [event]
           (swap! received conj event)
           true))]
    (sig/mount! scope)
    (runtime/flush! application)
    (let [node (nth (runtime/children application root) 0)]
      (is (= (Some (proto/StringValue "Native title"))
             (runtime-extension-property application node "title")))
      (sig/set! title "Updated title")
      (sig/stabilize! scheduler)
      (runtime/flush! application)
      (is (= (Some (proto/StringValue "Updated title"))
             (runtime-extension-property application node "title")))
      (runtime/dispatch!
       application (proto/ExtensionEvent node "native-view" "activate" {}))
      (sig/stabilize! scheduler)
      (is (= 1 (count (deref received)))))))

(deftest platform-attributes-lower-only-the-selected-ordered-tweaks
  (let [registry (ext/registry)
        _registered (ext/register-tweak! registry (ios-tweak-schema))
        batches (atom [])
        scheduler (sig/scheduler)
        application
        (runtime/create-with-extensions
         scheduler
         (recording-backend
          (proto/profile proto/IOS proto/SwiftUIHost) batches)
         registry)
        scope (sig/scope "tweak-authoring")
        root (platform-tweak-example (ui/context application scope))]
    (sig/mount! scope)
    (is (= "glass-card"
           (match (clojure.core/get
                   (deref (:runtime-extension-nodes application)) root)
             (Some identifier) identifier
             None "")))
    (let [inner (nth (runtime/children application root) 0)
          button (nth (runtime/children application inner) 0)]
      (is (= "glass-card"
             (match (clojure.core/get
                     (deref (:runtime-extension-nodes application)) inner)
               (Some identifier) identifier
               None "")))
      (is (= (Some (proto/BoolValue true))
             (runtime-extension-property application inner "prominent")))
      (is (= (Some proto/Button)
             (clojure.core/get (deref (:mounted-nodes application)) button)))))
  (let [registry (ext/registry)
        _registered (ext/register-tweak! registry (ios-tweak-schema))
        scheduler (sig/scheduler)
        application
        (runtime/create-with-extensions
         scheduler
         (recording-backend
          (proto/profile proto/AndroidOS proto/FlutterHost) (atom []))
         registry)
        scope (sig/scope "inactive-tweak")
        root (platform-tweak-example (ui/context application scope))]
    (sig/mount! scope)
    (is (= (Some proto/Button)
           (clojure.core/get (deref (:mounted-nodes application)) root)))
    (is (= 1 (runtime/mounted-count application))
        "non-matching platform keys create no decorator nodes"))
  (let [registry (ext/registry)
        _registered (ext/register-tweak! registry (ios-tweak-schema))
        scheduler (sig/scheduler)
        application
        (runtime/create-with-extensions
         scheduler
         (recording-backend
          (proto/profile proto/IOS proto/SwiftUIHost) (atom []))
         registry)
        scope (sig/scope "transparent-tweak")]
    (sig/mount! scope)
    (is (int? (tweaked-tab-example (ui/context application scope)))
        "a tweak is transparent to the parent's child-kind contract"))
  (let [registry (ext/registry)
        _registered (ext/register-tweak! registry (ios-tweak-schema))
        scheduler (sig/scheduler)
        application
        (runtime/create-with-extensions
         scheduler
         (recording-backend
          (proto/profile proto/IOS proto/SwiftUIHost) (atom []))
         registry)
        scope (sig/scope "reactive-tweak")
        prominent (sig/state scheduler (proto/BoolValue false))
        root
        (reactive-platform-tweak-example
         (ui/context application scope) (sig/value prominent))]
    (sig/mount! scope)
    (let [tweak-node root]
      (is (= (Some (proto/BoolValue false))
             (runtime-extension-property application tweak-node "prominent")))
      (sig/set! prominent (proto/BoolValue true))
      (sig/stabilize! scheduler)
      (is (= (Some (proto/BoolValue true))
             (runtime-extension-property application tweak-node "prominent")))
      (is (= root tweak-node)
          "reactive tweak properties preserve decorator identity"))))
