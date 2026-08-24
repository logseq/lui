(ns todos.model)

(defn initial []
  (record todo-model
    (model-items [])
    (model-draft "")
    (model-notes "")
    (model-next-id 0)))

(defn toggle-one [current id]
  (record todo
    (todo-id (:todo-id current))
    (todo-title (:todo-title current))
    (todo-done
     (if (= id (:todo-id current))
       (not (:todo-done current))
       (:todo-done current)))))

(defn toggle-items [items id]
  (mapv (fn [current] (toggle-one current id)) items))

(defn remove-item [items id]
  (filterv (fn [current] (not (= id (:todo-id current)))) items))

(defn move-item-up [items id]
  (loop [index 0]
    (if (= index (count items))
      items
      (if (= id (:todo-id (nth items index)))
        (if (= index 0)
          items
          (let [previous (nth items (dec index))
                current (nth items index)]
            (assoc (assoc items (dec index) current) index previous)))
        (recur (inc index))))))

(defn update [model action]
  (match action
    (ChangeDraft text)
    (record todo-model
      (model-items (:model-items model))
      (model-draft text)
      (model-notes (:model-notes model))
      (model-next-id (:model-next-id model)))

    (ChangeNotes text)
    (record todo-model
      (model-items (:model-items model))
      (model-draft (:model-draft model))
      (model-notes text)
      (model-next-id (:model-next-id model)))

    AddTodo
    (if (= "" (:model-draft model))
      (record todo-model
        (model-items (:model-items model))
        (model-draft (:model-draft model))
        (model-notes (:model-notes model))
        (model-next-id (:model-next-id model)))
      (let [id (inc (:model-next-id model))
            item
            (record todo
              (todo-id id)
              (todo-title (:model-draft model))
              (todo-done false))]
        (record todo-model
          (model-items (conj (:model-items model) item))
          (model-draft "")
          (model-notes (:model-notes model))
          (model-next-id id))))

    (ToggleTodo id)
    (record todo-model
      (model-items (toggle-items (:model-items model) id))
      (model-draft (:model-draft model))
      (model-notes (:model-notes model))
      (model-next-id (:model-next-id model)))

    (MoveTodoUp id)
    (record todo-model
      (model-items (move-item-up (:model-items model) id))
      (model-draft (:model-draft model))
      (model-notes (:model-notes model))
      (model-next-id (:model-next-id model)))

    (DeleteTodo id)
    (record todo-model
      (model-items (remove-item (:model-items model) id))
      (model-draft (:model-draft model))
      (model-notes (:model-notes model))
      (model-next-id (:model-next-id model)))))
