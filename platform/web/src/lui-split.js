// Bonsplit-style tabbed split panes — web renderer.
//
// The app owns the tree (see src/lui_split.ml); this module owns
// gesture-time visuals — drag previews, drop-zone highlight, live divider —
// so interactions run at display rate, and only committed actions are
// reported through the host.
//
// Host contract (duck-typed):
//   host.render(node)      -> HTMLElement for any node id (standard or
//                             extension children included)
//   host.emit(node, name, values)  -> report a committed event
//   host.extState(node)    -> { identifier, properties: {...}, children: [ids] }
//
// Entry points:
//   LUISplit.fingerprints  — schema literals, asserted in-sync by OCaml tests
//   LUISplit.render(node, host) — render a split extension node to DOM
//   LUISplit.mount(root, tree, onEvent) — standalone demo host: builds the
//     DOM from a plain-object tree and applies event semantics locally.
//
// Depends on lui-split.css.

const LUISplit = (() => {
  // Schema fingerprints — keep byte-identical with src/lui_split.ml output
  // and the literals in the other host files (checked by tests; the sync
  // checker extracts single-line literals, so keep each on one line).
  const fingerprints = {
    'split-view':
      'lui-extension-v1|10:split-view|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:12:split-branch,10:split-pane|properties:17:divider-thickness:float:optional:none,24:accessibility-identifier:string:optional:none,9:animation:bool:optional:none|events:',
    'split-branch':
      'lui-extension-v1|12:split-branch|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:12:split-branch,10:split-pane|properties:11:orientation:string:required:none,5:ratio:float:required:none|events:13:ratio-changed[5:ratio:float:required]',
    'split-pane':
      'lui-extension-v1|10:split-pane|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:9:split-tab|properties:24:accessibility-identifier:string:optional:none,7:focused:bool:optional:none,7:pane-id:string:required:none,8:selected:string:optional:none|events:10:split-drop[3:tab:string:required,4:edge:string:required,9:from-pane:string:required],10:tab-closed[3:tab:string:required],11:pane-closed[],12:pane-focused[],12:tab-selected[3:tab:string:required],15:split-requested[11:orientation:string:required],8:navigate[9:direction:string:required],9:tab-moved[3:tab:string:required,5:index:int:required,9:from-pane:string:required]',
    'split-tab':
      'lui-extension-v1|9:split-tab|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:1|children:|properties:24:accessibility-identifier:string:optional:none,4:icon:string:optional:none,5:dirty:bool:optional:none,5:title:string:required:none,6:tab-id:string:required:none,8:closable:bool:optional:none|events:',
  };

  const MIME = 'application/x-lui-split-tab';
  const prop = (state, name, fallback) =>
    state.properties[name] !== undefined ? state.properties[name] : fallback;

  // split-view: single child + settings broadcast via CSS vars on the root.
  function renderView(node, host) {
    const state = host.extState(node);
    const el = document.createElement('div');
    el.className = 'lui-split-view';
    const thickness = Number(prop(state, 'divider-thickness', 9));
    el.style.setProperty('--lui-split-divider', `${Math.max(1, thickness)}px`);
    if (!prop(state, 'animation', true)) el.dataset.animation = 'off';
    const id = prop(state, 'accessibility-identifier', '');
    if (id) el.dataset.testid = id;
    for (const child of state.children) el.append(host.render(child));
    return el;
  }

  // split-branch: two children separated by a draggable divider.
  function renderBranch(node, host) {
    const state = host.extState(node);
    const horizontal = prop(state, 'orientation', 'horizontal') !== 'vertical';
    let ratio = Number(prop(state, 'ratio', 0.5));

    const el = document.createElement('div');
    el.className = `lui-split-branch ${horizontal ? 'horizontal' : 'vertical'}`;
    const first = document.createElement('div');
    first.className = 'lui-split-branch-child';
    const divider = document.createElement('div');
    divider.className = 'lui-split-divider';
    divider.tabIndex = 0;
    divider.setAttribute('role', 'separator');
    divider.setAttribute(
      'aria-orientation', horizontal ? 'vertical' : 'horizontal');
    const second = document.createElement('div');
    second.className = 'lui-split-branch-child';
    if (state.children[0] !== undefined) {
      first.append(host.render(state.children[0]));
    }
    if (state.children[1] !== undefined) {
      second.append(host.render(state.children[1]));
    }
    el.append(first, divider, second);

    const apply = () => {
      first.style.flex = `${ratio} 1 0`;
      second.style.flex = `${1 - ratio} 1 0`;
      divider.setAttribute('aria-valuenow', Math.round(ratio * 100));
    };
    divider.setAttribute('aria-valuemin', '0');
    divider.setAttribute('aria-valuemax', '100');
    apply();

    let dragStart = null;
    divider.addEventListener('pointerdown', (event) => {
      dragStart = {
        ratio,
        point: horizontal ? event.clientX : event.clientY,
      };
      divider.setPointerCapture(event.pointerId);
      el.dataset.dragging = 'true';
      event.preventDefault();
    });
    divider.addEventListener('pointermove', (event) => {
      if (!dragStart) return;
      const span = horizontal ? el.clientWidth : el.clientHeight;
      const gap = dividerThickness(el);
      const available = Math.max(span - gap, 1);
      const point = horizontal ? event.clientX : event.clientY;
      ratio = Math.min(
        1, Math.max(0, dragStart.ratio + (point - dragStart.point) / available));
      apply();
    });
    const finish = () => {
      if (!dragStart) return;
      dragStart = null;
      delete el.dataset.dragging;
      host.emit(node, 'ratio-changed', { ratio });
    };
    divider.addEventListener('pointerup', finish);
    divider.addEventListener('pointercancel', finish);
    divider.addEventListener('keydown', (event) => {
      const delta = {
        ArrowLeft: horizontal ? -0.05 : 0,
        ArrowRight: horizontal ? 0.05 : 0,
        ArrowUp: !horizontal ? -0.05 : 0,
        ArrowDown: !horizontal ? 0.05 : 0,
      }[event.key];
      if (!delta) return;
      ratio = Math.min(1, Math.max(0, ratio + delta));
      apply();
      host.emit(node, 'ratio-changed', { ratio });
      event.preventDefault();
    });
    return el;
  }

  function dividerThickness(el) {
    const view = el.closest('.lui-split-view');
    if (!view) return 9;
    return parseFloat(
      view.style.getPropertyValue('--lui-split-divider')) || 9;
  }

  // split-pane: tab strip + content. Drops on content edges split the pane;
  // drops on the strip reorder/move tabs.
  function renderPane(node, host) {
    const state = host.extState(node);
    const paneId = String(prop(state, 'pane-id', ''));
    const focused = prop(state, 'focused', false);
    const tabs = state.children;

    const el = document.createElement('div');
    el.className = 'lui-split-pane';
    el.tabIndex = 0;
    el.dataset.paneId = paneId;
    if (focused) el.dataset.focused = 'true';
    if (host.registerPane) host.registerPane(node, el);
    const accId = prop(state, 'accessibility-identifier', '');
    if (accId) el.dataset.testid = accId;

    const strip = document.createElement('div');
    strip.className = 'lui-split-strip';
    strip.setAttribute('role', 'tablist');
    const content = document.createElement('div');
    content.className = 'lui-split-content';
    el.append(strip, content);

    const tabId = (tabNode) =>
      String(host.extState(tabNode).properties['tab-id'] ?? '');
    const selected = String(prop(state, 'selected', '')) ||
      (tabs.length ? tabId(tabs[0]) : '');

    tabs.forEach((tabNode, index) => {
      strip.append(renderChip(node, tabNode, index, selected, host));
    });
    strip.append(trailingIndicator(el));

    // Dropping on the strip body (past the last chip) appends to the pane.
    strip.addEventListener('dragover', (event) => {
      if (!event.dataTransfer.types.includes(MIME)) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
    });
    strip.addEventListener('drop', (event) => {
      const payload = event.dataTransfer.getData(MIME);
      event.preventDefault();
      const [fromPane, tab] = payload.split('\t');
      if (!tab) return;
      host.emit(node, 'tab-moved', {
        tab, 'from-pane': fromPane, index: tabs.length,
      });
    });

    tabs.forEach((tabNode, index) => {
      const child = host.render(tabNode);
      child.classList.add('lui-split-tab-content');
      const active = tabId(tabNode) === selected;
      child.dataset.active = active ? 'true' : 'false';
      child.inert = !active;
      content.append(child);
    });

    // Drop overlay — sized/anchored per zone.
    const overlay = document.createElement('div');
    overlay.className = 'lui-split-drop-overlay';
    overlay.dataset.zone = '';
    content.append(overlay);

    content.addEventListener('dragover', (event) => {
      if (!event.dataTransfer.types.includes(MIME)) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
      const rect = content.getBoundingClientRect();
      const ex = Math.min(Math.max(rect.width * 0.25, 48), 160);
      const ey = Math.min(Math.max(rect.height * 0.25, 48), 160);
      const x = event.clientX - rect.left;
      const y = event.clientY - rect.top;
      overlay.dataset.zone =
        x < ex ? 'left'
        : x > rect.width - ex ? 'right'
        : y < ey ? 'top'
        : y > rect.height - ey ? 'bottom'
        : 'center';
    });
    content.addEventListener('dragleave', (event) => {
      if (!content.contains(event.relatedTarget)) {
        overlay.dataset.zone = '';
      }
    });
    content.addEventListener('drop', (event) => {
      const zone = overlay.dataset.zone || 'center';
      overlay.dataset.zone = '';
      const payload = event.dataTransfer.getData(MIME);
      event.preventDefault();
      const [fromPane, tab] = payload.split('\t');
      if (!tab) return;
      if (zone === 'center') {
        host.emit(node, 'tab-moved', {
          tab, 'from-pane': fromPane, index: tabs.length,
        });
      } else {
        host.emit(node, 'split-drop', {
          tab, 'from-pane': fromPane, edge: zone,
        });
      }
    });

    el.addEventListener('pointerdown', () => {
      el.focus();
      host.emit(node, 'pane-focused', {});
    });

    el.addEventListener('keydown', (event) => {
      const mod = event.metaKey || event.ctrlKey;
      if (mod && event.altKey) {
        const direction = {
          ArrowLeft: 'left', ArrowRight: 'right',
          ArrowUp: 'up', ArrowDown: 'down',
        }[event.key];
        if (direction) {
          host.emit(node, 'navigate', { direction });
          event.preventDefault();
          return;
        }
        if (event.code === 'KeyD') {
          host.emit(node, 'split-requested', {
            orientation: event.shiftKey ? 'vertical' : 'horizontal',
          });
          event.preventDefault();
        }
      } else if (mod && event.key === '\\') {
        host.emit(node, 'split-requested', {
          orientation: event.shiftKey ? 'vertical' : 'horizontal',
        });
        event.preventDefault();
      } else if (mod && (event.key === 'w' || event.key === 'W')) {
        if (event.shiftKey) {
          host.emit(node, 'pane-closed', {});
        } else if (selected) {
          host.emit(node, 'tab-closed', { tab: selected });
        }
        event.preventDefault();
      }
    });
    return el;
  }

  function trailingIndicator(pane) {
    const el = document.createElement('div');
    el.className = 'lui-split-strip-indicator';
    el.dataset.visible = 'false';
    pane._stripIndicator = el;
    return el;
  }

  function renderChip(paneNode, tabNode, index, selected, host) {
    const state = host.extState(tabNode);
    const tabId = String(prop(state, 'tab-id', ''));
    const paneId = String(
      host.extState(paneNode).properties['pane-id'] ?? '');

    const chip = document.createElement('div');
    chip.className = 'lui-split-tab';
    chip.dataset.tab = tabId;
    chip.setAttribute('role', 'tab');
    chip.setAttribute('aria-selected', tabId === selected ? 'true' : 'false');
    chip.dataset.active = tabId === selected ? 'true' : 'false';
    chip.draggable = true;

    if (prop(state, 'dirty', false)) {
      const dot = document.createElement('span');
      dot.className = 'lui-split-tab-dirty';
      chip.append(dot);
    }
    const label = document.createElement('span');
    label.className = 'lui-split-tab-label';
    label.textContent = String(prop(state, 'title', tabId));
    chip.append(label);

    if (prop(state, 'closable', true)) {
      const close = document.createElement('button');
      close.className = 'lui-split-tab-close';
      close.type = 'button';
      close.setAttribute('aria-label', `Close ${label.textContent}`);
      close.textContent = '×';
      close.addEventListener('click', (event) => {
        event.stopPropagation();
        host.emit(paneNode, 'tab-closed', { tab: tabId });
      });
      chip.append(close);
    }

    chip.addEventListener('click', () => {
      host.emit(paneNode, 'tab-selected', { tab: tabId });
      host.emit(paneNode, 'pane-focused', {});
    });
    chip.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        host.emit(paneNode, 'tab-selected', { tab: tabId });
        event.preventDefault();
      }
    });

    chip.addEventListener('dragstart', (event) => {
      event.dataTransfer.setData(MIME, `${paneId}\t${tabId}`);
      event.dataTransfer.effectAllowed = 'move';
      chip.dataset.dragging = 'true';
    });
    chip.addEventListener('dragend', () => {
      delete chip.dataset.dragging;
    });

    // Reorder within the strip: drop on left/right half of a chip inserts
    // before/after it; the sibling indicator marks the target slot.
    chip.addEventListener('dragover', (event) => {
      if (!event.dataTransfer.types.includes(MIME)) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
      const rect = chip.getBoundingClientRect();
      const after = event.clientX - rect.left > rect.width / 2;
      chip.dataset.dropEdge = after ? 'after' : 'before';
    });
    chip.addEventListener('dragleave', () => {
      delete chip.dataset.dropEdge;
    });
    chip.addEventListener('drop', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const payload = event.dataTransfer.getData(MIME);
      const [fromPane, tab] = payload.split('\t');
      if (!tab) return;
      const rect = chip.getBoundingClientRect();
      const after = event.clientX - rect.left > rect.width / 2;
      delete chip.dataset.dropEdge;
      host.emit(paneNode, 'tab-moved', {
        tab, 'from-pane': fromPane, index: index + (after ? 1 : 0),
      });
    });
    return chip;
  }

  // split-tab: data carrier; stacks its standard children.
  function renderTab(node, host) {
    const el = document.createElement('div');
    el.className = 'lui-split-tab-node';
    for (const child of host.extState(node).children) {
      el.append(host.render(child));
    }
    return el;
  }

  const renderers = {
    'split-view': renderView,
    'split-branch': renderBranch,
    'split-pane': renderPane,
    'split-tab': renderTab,
  };

  function render(node, host) {
    const state = host.extState(node);
    const renderer = renderers[state.identifier];
    if (!renderer) {
      throw new Error(`lui-split: unknown identifier ${state.identifier}`);
    }
    return renderer(node, host);
  }

  // --- standalone demo host -------------------------------------------------
  // mount(root, tree, onEvent) renders a plain-object tree
  //   { identifier, properties, children: [node | {kind:'element', html}] }
  // and applies split semantics locally: move/split/close mutate the tree and
  // re-render. Useful for demos and for wiring a real transport later.
  function mount(root, tree, onEvent = () => {}, options = {}) {
    let index = 0;
    const byId = new Map();
    const fresh = () => `n${++index}`;
    const intern = (node) => {
      if (!node.id) node.id = fresh();
      byId.set(node.id, node);
      (node.children || []).forEach(intern);
      return node;
    };
    intern(tree);

    const paneEls = new Map();
    const host = {
      // Accepts node ids (normal render path) or child objects (demo trees
      // keep children inline).
      extState: (n) => (typeof n === 'object' ? n : byId.get(n)),
      registerPane: (node, el) => paneEls.set(node.id, el),
      render: (id) => {
        const node = byId.get(id) || id;
        if (node.identifier) return render(node.id, host);
        // Standard leaf: { element } wins; { html } renders as text unless
        // the caller marks the tree trusted with { allowHTML: true }.
        const div = document.createElement('div');
        if (node.element) div.append(node.element);
        else if (node.html && options.allowHTML) div.innerHTML = node.html;
        else div.textContent = node.html || '';
        return div;
      },
      emit: (node, name, values) => {
        onEvent(name, values);
        const kind = apply(tree, node, name, values);
        if (kind === 'focus') {
          // Focus is visual-only: patch the border in place so the
          // in-flight click/keyboard event keeps its target and focus.
          allPanes(tree).forEach((p) => {
            const el = paneEls.get(p.id);
            if (!el) return;
            if (p.properties.focused) el.dataset.focused = 'true';
            else delete el.dataset.focused;
          });
          setTimeout(focusModelPane, 0);
          return;
        }
        redraw();
      },
    };

    const focusModelPane = () => {
      // Model focus is authoritative — point real DOM focus at it so
      // navigate/close chains keep working after redraws.
      const pane = allPanes(tree).find((p) => p.properties.focused);
      const el = pane && paneEls.get(pane.id);
      if (el && typeof document !== 'undefined'
          && document.activeElement !== el) {
        el.focus();
      }
    };

    function redraw() {
      byId.clear();
      paneEls.clear();
      intern(tree);
      root.replaceChildren(render(tree.id, host));
      // Defer past the in-flight event: replacing the focused element
      // mid-handler makes the browser drop focus to <body> afterwards.
      const refocus = () => setTimeout(focusModelPane, 0);
      if (typeof setTimeout !== 'undefined') refocus();
    }
    redraw();

    // Minimal local semantics so demos feel alive: the real backend applies
    // these in OCaml and re-emits the tree.
    const allPanes = (rootNode) => {
      const panes = [];
      (function walk(n) {
        if (!n) return;
        if (n.identifier === 'split-pane') panes.push(n);
        (n.children || []).forEach(walk);
      })(rootNode);
      return panes;
    };

    function apply(rootNode, nodeId, name, values) {
      const node = byId.get(nodeId);
      if (!node) return;
      const parentOf = (from) => {
        const stack = [rootNode];
        while (stack.length) {
          const cur = stack.pop();
          if ((cur.children || []).some((c) => c.id === from)) return cur;
          (cur.children || []).forEach((c) => stack.push(c));
        }
        return null;
      };
      const findPane = (paneId) => {
        const stack = [rootNode];
        while (stack.length) {
          const cur = stack.pop();
          if (cur.properties && cur.properties['pane-id'] === paneId) {
            return cur;
          }
          (cur.children || []).forEach((c) => stack.push(c));
        }
        return null;
      };
      const setFocused = (pane) => {
        allPanes(rootNode).forEach(
          (p) => { p.properties.focused = p === pane; });
      };
      // Remove emptied panes and collapse degenerate branches; the root
      // view always keeps at least one pane.
      const prune = () => {
        let lastRemoved = null;
        (function walk(n) {
          if (!n.children) return;
          n.children.forEach(walk);
          n.children = n.children.filter((c) => {
            if (c.identifier === 'split-pane' && c.children.length === 0) {
              lastRemoved = c;
              return false;
            }
            return true;
          });
          n.children = n.children.flatMap((c) =>
            (c.identifier === 'split-branch' && c.children.length === 1)
              ? c.children
              : [c]);
        })(rootNode);
        if (!rootNode.children.length && lastRemoved) {
          rootNode.children = [lastRemoved];
        }
      };
      const splitPane = (pane, orientation, before = false) => {
        if (pane.children.length < 2) return;
        const selectedId = String(
          pane.properties.selected
          || (pane.children[0] ? pane.children[0].properties['tab-id'] : ''));
        if (!selectedId) return;
        const i = pane.children.findIndex(
          (c) => c.properties['tab-id'] === selectedId);
        if (i < 0) return;
        const [tab] = pane.children.splice(i, 1);
        if (pane.children.length) {
          pane.properties.selected =
            pane.children[Math.min(i, pane.children.length - 1)]
              .properties['tab-id'];
        }
        const freshPane = {
          identifier: 'split-pane',
          properties: { 'pane-id': fresh(), selected: selectedId,
                        focused: true },
          children: [tab],
        };
        const branch = {
          identifier: 'split-branch',
          properties: {
            orientation,
            // the fresh edge gets a quarter share, like Bonsplit
            ratio: before ? 0.25 : 0.75,
          },
          children: before ? [freshPane, pane] : [pane, freshPane],
        };
        const parent = parentOf(pane.id);
        if (parent) {
          parent.children[parent.children.indexOf(pane)] = branch;
        } else {
          Object.assign(rootNode, branch);
        }
        setFocused(freshPane);
        prune();
      };

      switch (name) {
        case 'tab-selected':
          node.properties.selected = values.tab;
          break;
        case 'pane-focused':
          setFocused(node);
          return 'focus';
        case 'ratio-changed':
          node.properties.ratio = values.ratio;
          break;
        case 'navigate': {
          const panes = allPanes(rootNode);
          const cur = panes.indexOf(node);
          if (cur < 0 || panes.length < 2) break;
          const step =
            (values.direction === 'left' || values.direction === 'up')
              ? -1 : 1;
          setFocused(
            panes[(cur + step + panes.length) % panes.length]);
          return 'focus';
        }
        case 'split-requested':
          splitPane(node, values.orientation);
          break;
        case 'pane-closed': {
          const panes = allPanes(rootNode);
          const cur = panes.indexOf(node);
          const parent = parentOf(node.id);
          if (!parent) break; // last pane stays
          parent.children.splice(parent.children.indexOf(node), 1);
          prune();
          const rest = allPanes(rootNode);
          if (rest.length) {
            setFocused(rest[Math.max(0, Math.min(cur, rest.length - 1))]);
          }
          break;
        }
        case 'tab-closed': {
          const i = (node.children || []).findIndex(
            (c) => c.properties['tab-id'] === values.tab);
          if (i >= 0) node.children.splice(i, 1);
          if (node.properties.selected === values.tab) {
            node.properties.selected = node.children[0]
              ? node.children[0].properties['tab-id']
              : '';
          }
          const hadTabs = node.children.length > 0;
          if (!hadTabs) {
            const panes = allPanes(rootNode);
            const cur = panes.indexOf(node);
            prune();
            const rest = allPanes(rootNode);
            if (rest.length) {
              setFocused(rest[Math.max(0, Math.min(cur, rest.length - 1))]);
            }
          }
          break;
        }
        case 'tab-moved': {
          const source = findPane(values['from-pane']);
          const target = node;
          if (!source || !target || !target.children) break;
          const i = (source.children || []).findIndex(
            (c) => c.properties['tab-id'] === values.tab);
          if (i < 0) break;
          const [tab] = source.children.splice(i, 1);
          // Same-pane move: the removed slot shifts the drop index.
          const index = source === target && values.index > i
            ? values.index - 1
            : values.index;
          target.children.splice(
            Math.min(index, target.children.length), 0, tab);
          target.properties.selected = values.tab;
          setFocused(target);
          if (source !== target) {
            if (source.children.length > 0) {
              source.properties.selected = source.children[0]
                .properties['tab-id'];
            } else {
              prune();
            }
          }
          break;
        }
        case 'split-drop': {
          const source = findPane(values['from-pane']);
          const target = node;
          if (!source) break;
          const horizontal =
            values.edge === 'left' || values.edge === 'right';
          const before =
            values.edge === 'left' || values.edge === 'top';
          if (source === target) {
            // Self split: move the dragged tab to a new edge pane.
            if (source.children.length < 2) break;
            const idx = source.children.findIndex(
              (c) => c.properties['tab-id'] === values.tab);
            if (idx < 0) break;
            source.properties.selected = values.tab;
            splitPane(source, horizontal ? 'horizontal' : 'vertical',
                      before);
          } else {
            const i = (source.children || []).findIndex(
              (c) => c.properties['tab-id'] === values.tab);
            if (i < 0) break;
            // Move the tab into the target pane first, then split it out
            // toward the edge so focus/orientation handling stays shared.
            const [tab] = source.children.splice(i, 1);
            target.children.push(tab);
            target.properties.selected = values.tab;
            if (source.children.length > 0) {
              source.properties.selected = source.children[0]
                .properties['tab-id'];
            }
            splitPane(target, horizontal ? 'horizontal' : 'vertical',
                      before);
          }
          break;
        }
        default:
          break;
      }
    }


    return { tree, redraw };
  }

  return { fingerprints, render, mount };
})();

if (typeof module !== 'undefined') module.exports = LUISplit;
if (typeof window !== 'undefined') window.LUISplit = LUISplit;
