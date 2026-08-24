(ns todos.app-test
  (:require [clojure.test :refer [deftest is]]
            [lui.protocol :as proto :refer [StringValue]]
            [lui.backend.apple :as apple]
            [lui.app :as driver]
            [todos.app :as todos]))

(defmacro assert-equal [expected actual message]
  `(is (= ~expected ~actual) ~message))

(deftest classic-todos-flow-is-reactive-and-retained
  (let [renderer (apple/create)
        application (todos/create (apple/backend renderer))]
    (driver/start! application)
    (driver/flush! application)
    (let [root-children (apple/children renderer (driver/root-node application))
          controls (nth root-children 1)
          scroll (nth root-children 2)
          input (nth (apple/children renderer controls) 0)
          add (nth (apple/children renderer controls) 1)
          list-node (nth (apple/children renderer scroll) 0)]
      (assert-equal [] (:model-items (todos/model application))
                    "the example starts empty")
      (assert-equal [] (apple/children renderer list-node)
                    "the retained list starts empty")

      (driver/dispatch-event!
       application (proto/TextChanged input "Write LG todos"))
      (driver/flush! application)
      (assert-equal "Write LG todos" (:model-draft (todos/model application))
                    "text input updates LG state")
      (driver/dispatch-event! application (proto/Press add))
      (driver/flush! application)

      (let [first-todo (nth (:model-items (todos/model application)) 0)
          first-row (nth (apple/children renderer list-node) 0)
          first-row-children (apple/children renderer first-row)
          first-label (nth first-row-children 0)
          first-toggle (nth first-row-children 1)
          first-delete (nth first-row-children 2)]
      (assert-equal "Write LG todos" (:todo-title first-todo)
                    "add creates a todo from the draft")
      (is (not (:todo-done first-todo)) "new todos are active")
      (assert-equal "" (:model-draft (todos/model application))
                    "add clears the draft")
      (match (apple/property renderer input proto/TextValue)
        (Some (StringValue text))
        (assert-equal "" text "the retained input follows cleared state")
        _ (is false "the input has a text value"))

      (driver/dispatch-event! application (proto/Press first-toggle))
      (driver/flush! application)
      (is (:todo-done
           (nth (:model-items (todos/model application)) 0))
          "toggle updates the typed todo model")
      (assert-equal first-row (nth (apple/children renderer list-node) 0)
                    "toggle preserves keyed row identity")
      (match (apple/property renderer first-label proto/TextValue)
        (Some (StringValue text))
        (assert-equal "[x] Write LG todos" text
                      "toggle updates only the retained label")
        _ (is false "the todo label has text"))

      (driver/dispatch-event!
       application (proto/TextChanged input "Ship Apple and Flutter"))
      (driver/flush! application)
      (driver/dispatch-event! application (proto/Press add))
      (driver/flush! application)
      (assert-equal 2 (count (:model-items (todos/model application)))
                    "a second todo is added")

      (driver/dispatch-event! application (proto/Press first-delete))
      (driver/flush! application)
      (assert-equal 1 (count (:model-items (todos/model application)))
                    "delete removes one todo")
      (assert-equal "Ship Apple and Flutter"
                    (:todo-title
                     (nth (:model-items (todos/model application)) 0))
                    "delete keeps the other todo")
      (match (apple/node renderer first-row)
        None (is true "the removed keyed subtree is dropped")
        _ (is false "the removed row must not remain"))))))
