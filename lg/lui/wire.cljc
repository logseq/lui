(ns lui.wire
  (:require [clojure.string :as string]
            [lui.wire-schema :as schema]
            [lui.protocol
             :refer [StringValue BoolValue IntValue FloatValue
                     CreateNode DropNode SetProp RemoveProp InsertChild RemoveChild
                     MoveChild CreateExtension SetExtensionProp
                     RemoveExtensionProp]]))

(defn- escape-json [value]
  (string/escape
   value
   {\\ "\\\\"
    \" "\\\""
    \newline "\\n"
    \return "\\r"
    \tab "\\t"}))

(defn- quoted [value]
  (str "\"" (escape-json value) "\""))

(defn- encode-value [value]
  (match value
    (StringValue text) (quoted text)
    (BoolValue enabled) (if enabled "true" "false")
    (IntValue number) (str number)
    (FloatValue number)
    (let [encoded (str number)]
      (if (or (string/includes? encoded ".")
              (string/includes? encoded "e")
              (string/includes? encoded "E"))
        (if (string/ends-with? encoded ".") (str encoded "0") encoded)
        (str encoded ".0")))))

(defn- encode-op [operation]
  (match operation
    (CreateNode node kind)
    (str "{\"op\":\"create-node\",\"id\":" node
         ",\"kind\":" (quoted (schema/node-kind-name kind)) "}")
    (CreateExtension node identifier fingerprint)
    (str "{\"op\":\"create-extension\",\"id\":" node
         ",\"identifier\":" (quoted identifier)
         ",\"fingerprint\":" (quoted fingerprint) "}")
    (DropNode node)
    (str "{\"op\":\"drop-node\",\"id\":" node "}")
    (SetProp node property value)
    (str "{\"op\":\"set-prop\",\"id\":" node
         ",\"property\":" (quoted (schema/property-name property))
         ",\"value\":" (encode-value value) "}")
    (RemoveProp node property)
    (str "{\"op\":\"remove-prop\",\"id\":" node
         ",\"property\":" (quoted (schema/property-name property)) "}")
    (SetExtensionProp node property value)
    (str "{\"op\":\"set-extension-prop\",\"id\":" node
         ",\"property\":" (quoted property)
         ",\"value\":" (encode-value value) "}")
    (RemoveExtensionProp node property)
    (str "{\"op\":\"remove-extension-prop\",\"id\":" node
         ",\"property\":" (quoted property) "}")
    (InsertChild parent child index)
    (str "{\"op\":\"insert-child\",\"parent\":" parent
         ",\"child\":" child ",\"index\":" index "}")
    (RemoveChild parent child)
    (str "{\"op\":\"remove-child\",\"parent\":" parent
         ",\"child\":" child "}")
    (MoveChild parent child index)
    (str "{\"op\":\"move-child\",\"parent\":" parent
         ",\"child\":" child ",\"index\":" index "}")))

(defn- encode-ops [operations]
  (loop [index 0
         encoded []]
    (if (= index (count operations))
      (string/join "," encoded)
      (recur (inc index) (conj encoded (encode-op (nth operations index)))))))

(defn encode-batch [batch]
  (str "{\"generation\":" (:generation batch)
       ",\"ops\":[" (encode-ops (:ops batch)) "]}"))
