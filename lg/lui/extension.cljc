(ns lui.extension
  (:require [clojure.string :as string]
            [lui.protocol :as proto
             :refer [GenericOS WebOS MacOS IOS AndroidOS LinuxOS WindowsOS
                     GenericHost WebHost SwiftUIHost FlutterHost
                     StringValue BoolValue IntValue FloatValue]]
            [lui.wire-schema :as wire-schema]))

(defn- valid-name? [value]
  (boolean (re-matches #"[a-z0-9]+(?:-[a-z0-9]+)*" value)))

(defn- scalar-value-supported? [kind value]
  (match (tuple kind value)
    (tuple StringScalar (StringValue _text)) true
    (tuple BoolScalar (BoolValue _enabled)) true
    (tuple IntScalar (IntValue _number)) true
    (tuple FloatScalar (FloatValue number)) (Float.is_finite number)
    _ false))

(defn property [name kind required default]
  (when-not (valid-name? name)
    (raise (Invalid_argument "invalid extension property name")))
  (match default
    (Some value)
    (when-not (scalar-value-supported? kind value)
      (raise (Invalid_argument "invalid extension property default")))
    None true)
  (record extension-property-schema
    (extension-property-name name)
    (extension-property-kind kind)
    (extension-property-required required)
    (extension-property-default default)))

(defn event-field [name kind required]
  (when-not (valid-name? name)
    (raise (Invalid_argument "invalid extension event field name")))
  (record extension-event-field-schema
    (extension-event-field-name name)
    (extension-event-field-kind kind)
    (extension-event-field-required required)))

(defn- duplicate-by-name? [values name-of]
  (loop [index 0
         seen (hash-map)]
    (if (= index (count values))
      false
      (let [name (name-of (nth values index))]
        (if (contains? seen name)
          true
          (recur (inc index) (assoc seen name true)))))))

(defn event [name fields]
  (when-not (valid-name? name)
    (raise (Invalid_argument "invalid extension event name")))
  (when (duplicate-by-name? fields :extension-event-field-name)
    (raise (Invalid_argument "duplicate extension event field")))
  (record extension-event-schema
    (extension-event-name name)
    (extension-event-fields fields)))

(defn component
  [identifier profiles standard-children child-identifiers properties events]
  (when-not (valid-name? identifier)
    (raise (Invalid_argument "invalid extension identifier")))
  (doseq [child child-identifiers]
    (when-not (valid-name? child)
      (raise (Invalid_argument "invalid extension child identifier"))))
  (when (duplicate-by-name? child-identifiers (fn [child] child))
    (raise (Invalid_argument "duplicate extension child identifier")))
  (when (duplicate-by-name? properties :extension-property-name)
    (raise (Invalid_argument "duplicate extension property")))
  (when (duplicate-by-name? events :extension-event-name)
    (raise (Invalid_argument "duplicate extension event")))
  (record extension-component-schema
    (extension-identifier identifier)
    (extension-profiles profiles)
    (extension-standard-children standard-children)
    (extension-child-identifiers child-identifiers)
    (extension-properties properties)
    (extension-events events)))

(defn tweak [identifier profiles properties]
  (component identifier profiles true [] properties []))

(defn- scalar-kind-name [kind]
  (match kind
    StringScalar "string"
    BoolScalar "bool"
    IntScalar "int"
    FloatScalar "float"))

(defn- operating-system-name [operating-system]
  (match operating-system
    GenericOS "generic"
    WebOS "web"
    MacOS "macos"
    IOS "ios"
    AndroidOS "android"
    LinuxOS "linux"
    WindowsOS "windows"))

(defn- host-name [host]
  (match host
    GenericHost "generic"
    WebHost "web"
    SwiftUIHost "swiftui"
    FlutterHost "flutter"))

(defn- token [value]
  (str (count value) ":" value))

(defn- wire-value-token [value]
  (match value
    (StringValue text) (str "s" (token text))
    (BoolValue enabled) (if enabled "b1" "b0")
    (IntValue number) (str "i" number)
    (FloatValue number) (str "f" number)))

(defn- option-value-token [value]
  (match value
    (Some current) (str "some:" (wire-value-token current))
    None "none"))

(defn- insert-sorted [values value]
  (loop [index 0
         result []]
    (if (= index (count values))
      (conj result value)
      (let [current (nth values index)]
        (if (<= (String.compare value current) 0)
          (into (conj result value) (subvec values index))
          (recur (inc index) (conj result current)))))))

(defn- sorted-strings [values]
  (reduce insert-sorted [] values))

(defn- profile-token [profile]
  (str (operating-system-name (:profile-os profile)) "/"
       (host-name (:profile-host profile))))

(defn- property-token [schema]
  (str
   (token (:extension-property-name schema)) ":"
   (scalar-kind-name (:extension-property-kind schema)) ":"
   (if (:extension-property-required schema) "required" "optional") ":"
   (option-value-token (:extension-property-default schema))))

(defn- event-field-token [schema]
  (str
   (token (:extension-event-field-name schema)) ":"
   (scalar-kind-name (:extension-event-field-kind schema)) ":"
   (if (:extension-event-field-required schema) "required" "optional")))

(defn- event-token [schema]
  (let [fields
        (sorted-strings
         (mapv event-field-token (:extension-event-fields schema)))]
    (str (token (:extension-event-name schema)) "["
         (string/join "," fields) "]")))

(defn fingerprint [schema]
  (let [profiles
        (sorted-strings (mapv profile-token (:extension-profiles schema)))
        children (sorted-strings (:extension-child-identifiers schema))
        properties
        (sorted-strings (mapv property-token (:extension-properties schema)))
        events (sorted-strings (mapv event-token (:extension-events schema)))]
    (str
     "lui-extension-v1|" (token (:extension-identifier schema))
     "|profiles:" (string/join "," profiles)
     "|standard-children:"
     (if (:extension-standard-children schema) "1" "0")
     "|children:" (string/join "," (mapv token children))
     "|properties:" (string/join "," properties)
     "|events:" (string/join "," events))))

(defn tweak-fingerprint [schema]
  (let [profiles
        (sorted-strings (mapv profile-token (:extension-profiles schema)))
        properties
        (sorted-strings (mapv property-token (:extension-properties schema)))]
    (str
     "lui-tweak-v1|" (token (:extension-identifier schema))
     "|profiles:" (string/join "," profiles)
     "|properties:" (string/join "," properties))))

(defn registry []
  (record extension-registry
    (extension-schemas (atom (hash-map)))
    (extension-tweak-identifiers (atom (hash-map)))
    (extension-registry-frozen (atom false))))

(defn register-component! [registry schema]
  (when (deref (:extension-registry-frozen registry))
    (raise (Invalid_argument "extension registry is frozen")))
  (let [identifier (:extension-identifier schema)]
    (when (wire-schema/standard-node-name? identifier)
      (raise (Invalid_argument "extension shadows a standard element")))
    (when (contains? (deref (:extension-schemas registry)) identifier)
      (raise (Invalid_argument "extension identifier is already registered")))
    (swap! (:extension-schemas registry) assoc identifier schema)
    true))

(defn register-tweak! [registry schema]
  (when (deref (:extension-registry-frozen registry))
    (raise (Invalid_argument "extension registry is frozen")))
  (let [identifier (:extension-identifier schema)]
    (when (wire-schema/standard-node-name? identifier)
      (raise (Invalid_argument "tweak shadows a standard element")))
    (when (contains? (deref (:extension-schemas registry)) identifier)
      (raise (Invalid_argument "extension identifier is already registered")))
    (when (or
           (not (:extension-standard-children schema))
           (not (empty? (:extension-child-identifiers schema)))
           (not (empty? (:extension-events schema))))
      (raise (Invalid_argument "invalid tweak schema")))
    (swap! (:extension-schemas registry) assoc identifier schema)
    (swap! (:extension-tweak-identifiers registry) assoc identifier true)
    true))

(defn freeze! [registry]
  (if (deref (:extension-registry-frozen registry))
    true
    (let [schemas (deref (:extension-schemas registry))]
      (reduce-kv
       (fn [_valid _identifier schema]
         (doseq [child (:extension-child-identifiers schema)]
           (when-not (contains? schemas child)
             (raise (Invalid_argument "unknown extension child schema"))))
         true)
       true
       schemas)
      (reset! (:extension-registry-frozen registry) true)
      true)))

(defn frozen? [registry]
  (deref (:extension-registry-frozen registry)))

(defn schema [registry identifier]
  (clojure.core/get (deref (:extension-schemas registry)) identifier))

(defn tweak? [registry identifier]
  (contains? (deref (:extension-tweak-identifiers registry)) identifier))

(defn profile-supported? [schema profile]
  (loop [index 0]
    (if (= index (count (:extension-profiles schema)))
      false
      (if (= profile (nth (:extension-profiles schema) index))
        true
        (recur (inc index))))))

(defn standard-container-supported? [kind]
  (or
   (= kind proto/Root) (= kind proto/Row) (= kind proto/Column) (= kind proto/Grid)
   (= kind proto/Stack) (= kind proto/Panel) (= kind proto/Card)
   (= kind proto/Box) (= kind proto/Scroll) (= kind proto/ListContainer)
   (= kind proto/ListItem) (= kind proto/Dialog)
   (= kind proto/Sheet) (= kind proto/Accordion) (= kind proto/Resizable)
   (= kind proto/Split) (= kind proto/Alert) (= kind proto/Bubble)))

(defn identifier-allowed? [identifiers identifier]
  (loop [index 0]
    (if (= index (count identifiers))
      false
      (if (= identifier (nth identifiers index))
        true
        (recur (inc index))))))

(defn- property-schema [schema name]
  (loop [index 0]
    (if (= index (count (:extension-properties schema)))
      None
      (let [current (nth (:extension-properties schema) index)]
        (if (= name (:extension-property-name current))
          (Some current)
          (recur (inc index)))))))

(defn property-value-supported? [schema name value]
  (match (property-schema schema name)
    (Some current)
    (scalar-value-supported? (:extension-property-kind current) value)
    None false))

(defn property-supported? [schema name]
  (match (property-schema schema name)
    (Some _current) true
    None false))

(defn properties-supported? [schema values]
  (and
   (reduce-kv
    (fn [valid name value]
      (and valid (property-value-supported? schema name value)))
    true
    values)
   (loop [index 0]
     (if (= index (count (:extension-properties schema)))
       true
       (let [property (nth (:extension-properties schema) index)]
         (if (and
              (:extension-property-required property)
              (not (contains? values (:extension-property-name property)))
              (match (:extension-property-default property)
                (Some _default) false
                None true))
           false
           (recur (inc index))))))))

(defn- event-schema [schema name]
  (loop [index 0]
    (if (= index (count (:extension-events schema)))
      None
      (let [current (nth (:extension-events schema) index)]
        (if (= name (:extension-event-name current))
          (Some current)
          (recur (inc index)))))))

(defn- event-field-schema [schema name]
  (loop [index 0]
    (if (= index (count (:extension-event-fields schema)))
      None
      (let [current (nth (:extension-event-fields schema) index)]
        (if (= name (:extension-event-field-name current))
          (Some current)
          (recur (inc index)))))))

(defn- required-event-fields-present? [schema values]
  (loop [index 0]
    (if (= index (count (:extension-event-fields schema)))
      true
      (let [field (nth (:extension-event-fields schema) index)]
        (if (and
             (:extension-event-field-required field)
             (not (contains? values (:extension-event-field-name field))))
          false
          (recur (inc index)))))))

(defn event-payload-supported? [schema name values]
  (match (event-schema schema name)
    (Some current)
    (and
     (required-event-fields-present? current values)
     (reduce-kv
      (fn [valid field-name value]
        (and
         valid
         (match (event-field-schema current field-name)
           (Some field)
           (scalar-value-supported?
            (:extension-event-field-kind field) value)
           None false)))
      true
      values))
    None false))
