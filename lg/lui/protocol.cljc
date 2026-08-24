(ns lui.protocol)

(defn event-node [event]
  (match event
    (Press node) node
    (TextChanged node _text) node))

(defn property-supported? [kind property]
  (match property
    PaddingValue true
    BackgroundValue true
    TextValue
    (match kind
      Text true
      Button true
      TextInput true
      _ false)
    Enabled
    (match kind
      Button true
      TextInput true
      _ false)
    Gap
    (match kind
      Row true
      Column true
      _ false)))

(defn create-node-op [node kind]
  (CreateNode node kind))

(defn drop-node-op [node]
  (DropNode node))

(defn set-prop-op [node property value]
  (SetProp node property value))

(defn insert-child-op [parent child index]
  (InsertChild parent child index))

(defn remove-child-op [parent child]
  (RemoveChild parent child))

(defn move-child-op [parent child index]
  (MoveChild parent child index))
