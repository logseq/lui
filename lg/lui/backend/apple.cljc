(ns lui.backend.apple
  (:require [lui.protocol :as proto
             :refer [Row Column Box Text Heading Paragraph Label Button
                     TextInput TextArea Scroll Spacer]]
            [lui.backend.retained :as retained]
            [lui.wire :as wire]))

(defn create
  ([] (create (fn [_batch] true)))
  ([send-batch]
   (record apple-renderer
     (apple-store (retained/create-store))
     (apple-send-batch send-batch))))

(defn create-wire [send-json]
  (create (fn [batch] (send-json (wire/encode-batch batch)))))

(defn- platform-node [kind]
  (match kind
    Row AppleRow
    Column AppleColumn
    Box AppleBox
    Text AppleLabel
    Heading AppleHeading
    Paragraph AppleParagraph
    Label AppleFormLabel
    Button AppleButton
    TextInput AppleTextInput
    TextArea AppleTextArea
    Scroll AppleScrollView
    Spacer AppleSpacer))

(defn backend-for [renderer operating-system host]
  (record proto/backend
    (backend-profile (proto/profile operating-system host))
    (apply-batch
     (fn [batch]
       (retained/apply-batch-with!
        (:apple-store renderer) platform-node
        (:apple-send-batch renderer) batch)))))

(defn backend [renderer]
  (backend-for renderer proto/MacOS proto/AppKitHost))

(defn- some-node [value]
  (Some value))

(defn node [renderer node]
  (match (retained/node (:apple-store renderer) node)
    (Some current) (some-node (:platform-node current))
    None None))

(defn property [renderer node property]
  (retained/property (:apple-store renderer) node property))

(defn children [renderer node]
  (retained/children (:apple-store renderer) node))

(defn node-count [renderer]
  (retained/node-count (:apple-store renderer)))

(defn batches [renderer]
  (retained/batches (:apple-store renderer)))
