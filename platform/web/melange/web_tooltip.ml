let install : unit -> unit =
  [%raw
    {|
    function () {
      const coordinatorKey = Symbol.for("lui.web.tooltip-coordinator");
      if (globalThis[coordinatorKey]) return;

      const warmDuration = 400;
      const leaveGrace = 50;
      const records = new WeakMap();
      let warmUntil = 0;
      let active = null;

      const directTrigger = (tooltip) =>
        Array.from(tooltip.parentElement?.children || []).find(
          (child) => child !== tooltip && !child.matches(".lui-tooltip[data-anchor]"),
        );

      const addDescription = (trigger, id) => {
        if (!trigger || !id) return;
        const ids = new Set((trigger.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean));
        ids.add(id);
        trigger.setAttribute("aria-describedby", Array.from(ids).join(" "));
      };

      const removeDescription = (trigger, id) => {
        if (!trigger || !id) return;
        const ids = (trigger.getAttribute("aria-describedby") || "")
          .split(/\s+/)
          .filter((value) => value && value !== id);
        if (ids.length) trigger.setAttribute("aria-describedby", ids.join(" "));
        else trigger.removeAttribute("aria-describedby");
      };

      const position = (record) => {
        const { tooltip, host } = record;
        if (!tooltip.matches(":popover-open")) return;
        const hostRect = host.getBoundingClientRect();
        const tooltipRect = tooltip.getBoundingClientRect();
        const offset = Number.parseFloat(tooltip.dataset.anchorOffset || "4") || 0;
        const preferredAbove = tooltip.dataset.anchor === "above";
        const roomAbove = hostRect.top;
        const roomBelow = innerHeight - hostRect.bottom;
        const above = preferredAbove
          ? roomAbove >= tooltipRect.height + offset || roomAbove >= roomBelow
          : !(roomBelow >= tooltipRect.height + offset || roomBelow >= roomAbove);
        const alignment = tooltip.dataset.anchorAlignment || "start";
        let left = hostRect.left;
        if (alignment === "end") left = hostRect.right - tooltipRect.width;
        if (alignment === "stretch") {
          left = hostRect.left;
          tooltip.style.width = `${hostRect.width}px`;
        } else {
          tooltip.style.removeProperty("width");
        }
        left = Math.max(4, Math.min(left, innerWidth - tooltipRect.width - 4));
        const top = above
          ? hostRect.top - tooltipRect.height - offset
          : hostRect.bottom + offset;
        tooltip.style.left = `${left}px`;
        tooltip.style.top = `${Math.max(4, Math.min(top, innerHeight - tooltipRect.height - 4))}px`;
        tooltip.dataset.resolvedAnchor = above ? "above" : "below";
      };

      const cancelTimers = (record) => {
        clearTimeout(record.showTimer);
        clearTimeout(record.hideTimer);
        record.showTimer = 0;
        record.hideTimer = 0;
      };

      const hide = (record, { warm = false, clearWarm = false } = {}) => {
        cancelTimers(record);
        if (warm && record.origin === "pointer" && record.tooltip.matches(":popover-open")) {
          warmUntil = performance.now() + warmDuration;
        }
        if (clearWarm) warmUntil = 0;
        if (record.tooltip.matches(":popover-open")) record.tooltip.hidePopover();
        record.origin = null;
        if (active === record) active = null;
      };

      const show = (record, origin) => {
        clearTimeout(record.showTimer);
        record.showTimer = 0;
        if (!record.tooltip.isConnected || !record.host.isConnected) return;
        if (active && active !== record) hide(active);
        record.origin = origin;
        if (!record.tooltip.matches(":popover-open")) record.tooltip.showPopover();
        active = record;
        requestAnimationFrame(() => position(record));
      };

      const schedulePointerShow = (record) => {
        clearTimeout(record.hideTimer);
        const configured = Number.parseInt(record.tooltip.dataset.tooltipDelay || "600", 10);
        const delay = performance.now() < warmUntil ? 0 : Math.max(0, configured);
        if (delay === 0) show(record, "pointer");
        else record.showTimer = setTimeout(() => show(record, "pointer"), delay);
      };

      const installTooltip = (tooltip) => {
        if (records.has(tooltip) || !tooltip.matches(".lui-tooltip[data-anchor]")) return;
        const host = tooltip.parentElement;
        const trigger = directTrigger(tooltip);
        if (!host || !trigger) return;
        const record = {
          tooltip,
          host,
          trigger,
          origin: null,
          pointerInHost: false,
          pointerInTooltip: false,
          showTimer: 0,
          hideTimer: 0,
          cleanup: null,
        };
        records.set(tooltip, record);
        addDescription(trigger, tooltip.id);

        const pointerEnteredHost = () => {
          record.pointerInHost = true;
          schedulePointerShow(record);
        };
        const pointerLeftHost = () => {
          record.pointerInHost = false;
          clearTimeout(record.showTimer);
          record.showTimer = 0;
          if (record.origin === "pointer" && tooltip.matches(":popover-open")) {
            warmUntil = performance.now() + warmDuration;
          }
          record.hideTimer = setTimeout(() => {
            if (!record.pointerInHost && !record.pointerInTooltip) hide(record);
          }, leaveGrace);
        };
        const pointerEnteredTooltip = () => {
          record.pointerInTooltip = true;
          clearTimeout(record.hideTimer);
        };
        const pointerLeftTooltip = () => {
          record.pointerInTooltip = false;
          if (!record.pointerInHost) hide(record, { warm: true });
        };
        const focusEntered = () => show(record, "focus");
        const focusLeft = () => queueMicrotask(() => {
          if (!host.contains(document.activeElement) && !record.pointerInHost && !record.pointerInTooltip) {
            hide(record);
          }
        });
        const pressed = () => hide(record, { clearWarm: true });

        host.addEventListener("pointerenter", pointerEnteredHost);
        host.addEventListener("pointerleave", pointerLeftHost);
        tooltip.addEventListener("pointerenter", pointerEnteredTooltip);
        tooltip.addEventListener("pointerleave", pointerLeftTooltip);
        host.addEventListener("focusin", focusEntered);
        host.addEventListener("focusout", focusLeft);
        host.addEventListener("pointerdown", pressed, true);
        record.cleanup = () => {
          hide(record);
          removeDescription(trigger, tooltip.id);
          host.removeEventListener("pointerenter", pointerEnteredHost);
          host.removeEventListener("pointerleave", pointerLeftHost);
          tooltip.removeEventListener("pointerenter", pointerEnteredTooltip);
          tooltip.removeEventListener("pointerleave", pointerLeftTooltip);
          host.removeEventListener("focusin", focusEntered);
          host.removeEventListener("focusout", focusLeft);
          host.removeEventListener("pointerdown", pressed, true);
          records.delete(tooltip);
        };
      };

      const scan = (root) => {
        if (!(root instanceof Element)) return;
        if (root.matches(".lui-tooltip[data-anchor]")) installTooltip(root);
        root.querySelectorAll(".lui-tooltip[data-anchor]").forEach(installTooltip);
      };

      const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          if (mutation.type === "attributes") {
            const tooltip = mutation.target;
            if (tooltip.matches(".lui-tooltip[data-anchor]")) installTooltip(tooltip);
            const record = records.get(tooltip);
            if (record && active === record) position(record);
          }
          if (mutation.type === "characterData" || mutation.type === "childList") {
            const element = mutation.target.nodeType === Node.ELEMENT_NODE
              ? mutation.target
              : mutation.target.parentElement;
            const tooltip = element?.closest?.(".lui-tooltip[data-anchor]");
            const record = tooltip && records.get(tooltip);
            if (record && active === record) position(record);
          }
          for (const node of mutation.addedNodes) scan(node);
          for (const node of mutation.removedNodes) {
            if (!(node instanceof Element)) continue;
            const removed = node.matches(".lui-tooltip")
              ? [node]
              : Array.from(node.querySelectorAll(".lui-tooltip"));
            removed.forEach((tooltip) => records.get(tooltip)?.cleanup());
          }
        }
      });

      const dismiss = (event) => {
        if (event.key === "Escape" && active) hide(active, { clearWarm: true });
      };
      const reposition = () => active && position(active);
      const blur = () => active && hide(active, { clearWarm: true });
      document.addEventListener("keydown", dismiss, true);
      window.addEventListener("blur", blur);
      window.addEventListener("resize", reposition);
      window.addEventListener("scroll", reposition, true);
      observer.observe(document, {
        subtree: true,
        childList: true,
        characterData: true,
        attributes: true,
        attributeFilter: ["data-anchor", "data-anchor-alignment", "data-anchor-offset", "data-tooltip-delay"],
      });
      document.querySelectorAll(".lui-tooltip[data-anchor]").forEach(installTooltip);
      globalThis[coordinatorKey] = { observer };
    }
    |}]
