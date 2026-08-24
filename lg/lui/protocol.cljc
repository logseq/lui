(ns lui.protocol)

(defn profile [operating-system host]
  (record platform-profile
    (profile-os operating-system)
    (profile-host host)))

(defn generic-profile []
  (profile GenericOS GenericHost))

(defn event-node [event]
  (match event
    (Press node) node
    (TextChanged node _text) node))

(defn event-supported? [kind event]
  (match event
    (Press _node) (= kind Button)
    (TextChanged _node _text) (= kind TextInput)))

(defn property-supported? [kind property]
  (match property
    PaddingValue true
    BackgroundValue true
    AccessibilityLabel (= kind TextInput)
    PlaceholderValue (= kind TextInput)
    ReadOnly (= kind TextInput)
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

(defn property-value-supported? [property value]
  (match (tuple property value)
    (tuple TextValue (StringValue _value)) true
    (tuple Enabled (BoolValue _value)) true
    (tuple Gap (IntValue _value)) true
    (tuple PaddingValue (IntValue _value)) true
    (tuple BackgroundValue (StringValue _value)) true
    (tuple PlaceholderValue (StringValue _value)) true
    (tuple ReadOnly (BoolValue _value)) true
    (tuple AccessibilityLabel (StringValue _value)) true
    _ false))

(defn can-contain-children? [kind]
  (match kind
    Row true
    Column true
    Scroll true
    _ false))

(defn single-child-container? [kind]
  (= kind Scroll))

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
