let install : unit -> unit =
  [%raw
    {|
    function () {
      const observerKey = Symbol.for("lui.web.dialog-observer");
      if (globalThis[observerKey]) return;
      const sync = (dialog) => {
        const state = dialog.getAttribute("data-lui-modal-state");
        if (state === "open" && !dialog.open) dialog.showModal();
        if (state === "closed" && dialog.open) dialog.close();
      };
      const observer = new MutationObserver((records) => {
        for (const record of records) {
          if (record.type === "attributes" && record.target instanceof HTMLDialogElement) {
            sync(record.target);
          }
          for (const node of record.addedNodes) {
            if (!(node instanceof Element)) continue;
            if (node instanceof HTMLDialogElement) sync(node);
            node.querySelectorAll("dialog[data-lui-modal-state]").forEach(sync);
          }
        }
      });
      observer.observe(document, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ["data-lui-modal-state"],
      });
      globalThis[observerKey] = observer;
      document.querySelectorAll("dialog[data-lui-modal-state]").forEach(sync);
    }
    |}]
