//! LUI control semantics composed from public NSH behavior components.
use crate::{render::Event, store::Node, ui};
use nsh_core::{
    StyleDecl, StyleKey,
    element::{ComponentElement, Style, StyleRefinement},
    geometry::{Axis, Points},
    prelude::*,
};
use std::{cell::RefCell, rc::Rc, sync::Arc};

mod basic;
mod collections;
mod navigation;
mod surfaces;
pub(crate) mod toasts;
pub(crate) mod tree;

/// Sparse access to existing retained child signals, without a second tree.
pub(crate) type ChildIdentity = (u64, u64);
type ChildLookup = Rc<dyn Fn(ChildIdentity) -> Option<Signal<Arc<Node>>>>;

#[derive(Clone)]
pub(crate) struct ChildRenderer {
    pub identities: Signal<Vec<ChildIdentity>>,
    pub render: Rc<dyn Fn(ChildIdentity) -> AnyElement>,
    pub lookup: ChildLookup,
    /// Forwards an actual native child activation with its own identity guard.
    pub press: Rc<dyn Fn(ChildIdentity)>,
}

/// The renderer supplies identity and authored presentation before type erasure.
pub(crate) struct Presentation {
    pub key: SharedString,
    pub test_id: SharedString,
    pub style: Rc<dyn Fn() -> Style>,
    pub reference: ElementRef,
    pub theme: ui::Theme,
    pub events: Option<crate::events::NativeEvents>,
    pub children: Option<ChildRenderer>,
}
impl Presentation {
    fn component_identity<C: Component>(&self, element: ComponentElement<C>) -> AnyElement {
        element
            .key(self.key.clone())
            .element_ref(&self.reference)
            .test_id(&self.test_id)
            .into_element()
    }
    fn host_identity<E: Element + Interactive>(&self, element: E) -> AnyElement {
        let element = match &self.events {
            Some(events) => events.attach(element),
            None => element,
        };
        element
            .key(self.key.clone())
            .element_ref(&self.reference)
            .test_id(&self.test_id)
            .into_element()
    }
    fn component<C: Component>(&self, element: ComponentElement<C>) -> AnyElement {
        let style = self.style.clone();
        element
            .key(self.key.clone())
            .element_ref(&self.reference)
            .test_id(&self.test_id)
            .state_inline_style(move || style())
            .into_element()
    }
    /// A page owns layout and appearance; its separate native Tab owns presses.
    fn passive_host<E: Element + Interactive>(&self, element: E) -> AnyElement {
        let style = self.style.clone();
        element
            .key(self.key.clone())
            .element_ref(&self.reference)
            .test_id(&self.test_id)
            .state_inline_style(move || style())
            .into_element()
    }
    fn host<E: Element + Interactive>(&self, element: E) -> AnyElement {
        let element = match &self.events {
            Some(events) => events.attach(element),
            None => element,
        };
        let style = self.style.clone();
        element
            .key(self.key.clone())
            .element_ref(&self.reference)
            .test_id(&self.test_id)
            .state_inline_style(move || style())
            .into_element()
    }
}

type Emit = Rc<dyn Fn(Event)>;
pub(crate) struct PopupCallbacks {
    pub render: Rc<dyn Fn(u64) -> AnyElement>,
    pub dismiss: Rc<dyn Fn(u64)>,
}

/// LUI owns picker values and the structural lifetime of its popup. Native
/// Menu owns traversal, focus restoration, submenu behavior and dismissal.
pub(crate) fn picker(
    node: Signal<Arc<Node>>,
    popup: Signal<Option<(u64, u64)>>,
    children: AnyElement,
    callbacks: PopupCallbacks,
    emit: Emit,
    submenu: bool,
    presentation: Presentation,
) -> AnyElement {
    let PopupCallbacks { render, dismiss } = callbacks;
    let id = node.get_untracked().id;
    let theme = presentation.theme;
    let kind = node.get_untracked().kind.clone();
    let trigger = if kind == "combobox" {
        let change = emit.clone();
        presentation.host(
            crate::inputs::attach(ui::input(theme), node, emit.clone())
                .value(move || node.get().string("text").to_owned())
                .placeholder(move || node.get().string("placeholder").to_owned())
                .readonly(move || node.get().boolean("read-only", false))
                .disabled(move || !enabled(node))
                .label(move || label(node))
                .on_change(move |value: &str| {
                    emit_flag(
                        node,
                        "change-enabled",
                        &change,
                        Event::Text(id, value.into()),
                    )
                }),
        )
    } else {
        presentation.host(
            ui::menu_trigger(theme)
                .disabled(move || !enabled(node))
                .label(move || label(node))
                .child(text(move || {
                    let node = node.get();
                    let text = node.string("text");
                    if text.is_empty() {
                        node.string("placeholder").to_owned()
                    } else {
                        text.to_owned()
                    }
                }))
                .child(if kind == "menu-trigger" {
                    view().into_element()
                } else {
                    children
                }),
        )
    };
    if submenu {
        return nsh_base::Submenu::element(nsh_base::SubmenuProps {
            disabled: Prop::bind(move || !enabled(node)),
            ..Default::default()
        })
        .fill("trigger", trigger)
        .child(dynamic(move || {
            node.get().children.first().copied().map(|id| render(id))
        }))
        .on_event(move |event: &nsh_base::SubmenuEvent| {
            if matches!(
                event,
                nsh_base::SubmenuEvent::OpenChange(false, nsh_base::OpenChangeReason::Cancel)
            ) && let Some(id) = node.get_untracked().children.first()
            {
                dismiss(*id);
            }
        })
        .into_element();
    }
    let controlled = kind != "menu-trigger";
    let props = nsh_base::MenuProps {
        open: Prop::bind(move || controlled.then(|| popup.get().is_some())),
        popup_class: Some("p-1 gap-1 border rounded-(--radius)".into()).into(),
        popup_style: Prop::bind(move || {
            ui::part(
                StyleRefinement::default()
                    .bg(ui::color(theme, "popover"))
                    .text_color(ui::color(theme, "popover-foreground"))
                    .border_color(ui::color(theme, "border"))
                    .rounded(ui::radius(theme)),
            )
        }),
        ..Default::default()
    };
    nsh_base::Menu::element(props)
        .fill("trigger", trigger)
        .child(dynamic(move || {
            let target = if controlled {
                popup.get().map(|(id, _)| id)
            } else {
                node.get().children.first().copied()
            };
            target.map(|id| render(id))
        }))
        .on_event(move |event: &nsh_base::MenuEvent| match event {
            nsh_base::MenuEvent::OpenChange(_, nsh_base::OpenChangeReason::TriggerPress)
                if controlled =>
            {
                emit_flag(node, "press-enabled", &emit, Event::Press(id))
            }
            nsh_base::MenuEvent::Cancel => {
                let target = if controlled {
                    popup.get_untracked().map(|(id, _)| id)
                } else {
                    node.get_untracked().children.first().copied()
                };
                if let Some(id) = target {
                    dismiss(id);
                }
            }
            _ => {}
        })
        .into_element()
}

/// External LUI anchors use the core's native placement and hint policy.
pub(crate) fn anchored_popup(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    anchor: Option<ElementRef>,
    emit: Emit,
    presentation: Presentation,
) -> AnyElement {
    let id = node.get_untracked().id;
    let theme = presentation.theme;
    let tip = node.get_untracked().kind == "tooltip";
    let mut popup = overlay()
        .placement(move || match node.get().string("anchor") {
            "above" => Placement::Top,
            "left" => Placement::Left,
            "right" => Placement::Right,
            _ => Placement::Bottom,
        })
        .align(move || match node.get().string("anchor-alignment") {
            "end" => Align::End,
            "center" => Align::Center,
            _ => Align::Start,
        })
        .offset(move || px(node.get().number("anchor-offset", 0.0) as f32))
        .margin(move || px(node.get().number("collision-padding", 8.0) as f32));
    if !node.get_untracked().string("anchor-rect").is_empty() {
        popup = popup.anchor_bounds(move || {
            popup_rectangle(node.get().string("anchor-rect")).expect("validated popup rectangle")
        });
    } else if node.get_untracked().props.contains_key("x") {
        popup = popup.anchor_point(move || nsh_core::geometry::Point {
            x: px(node.get().number("x", 0.0) as f32),
            y: px(node.get().number("y", 0.0) as f32),
        });
    } else if let Some(anchor) = anchor {
        popup = popup.anchor(&anchor);
    }
    if tip {
        return presentation.host(
            popup
                .hint(move || {
                    std::time::Duration::from_secs_f64(
                        node.get().number("tooltip-delay", 600.0) / 1000.0,
                    )
                })
                .pointer_events(PointerEvents::None)
                .p_2()
                .rounded(move || ui::radius(theme))
                .bg(move || ui::color(theme, "popover"))
                .text_color(move || ui::color(theme, "popover-foreground"))
                .child(text(move || node.get().string("text").to_owned())),
        );
    }
    let inside = Rc::new(std::cell::Cell::new(false));
    let restore = Rc::new(std::cell::Cell::new(true));
    let entered = inside.clone();
    presentation
        .reference
        .on_focus_in(move || entered.set(true));
    let left = inside.clone();
    presentation.reference.on_focus_out(move || left.set(false));
    let outside_restore = restore.clone();
    cleanup(move || {
        if inside.get()
            && restore.get()
            && let Some(anchor) = anchor
        {
            anchor.focus();
        }
    });
    let outside = emit.clone();
    let width = signal(px(0.0));
    if let Some(anchor) = anchor {
        spawn(async move {
            if let Some(measured) = anchor.measure().await {
                width.set(measured.frame.size.width);
            }
        });
    }
    presentation.host(
        popup
            .role(AccessibilityRole::Dialog)
            .p_3()
            .gap_2()
            .rounded(move || ui::radius(theme))
            .border_1()
            .bg(move || ui::color(theme, "popover"))
            .text_color(move || ui::color(theme, "popover-foreground"))
            .border_color(move || ui::color(theme, "border"))
            .style_with(move |s| {
                let n = node.get();
                let s = if n.string("anchor-alignment") == "stretch" {
                    s.min_w(width.get())
                } else {
                    s
                };
                if n.props.contains_key("available-height") {
                    s.max_h(px(n.number("available-height", 0.0) as f32))
                        .overflow_hidden()
                } else {
                    s
                }
            })
            .on_press_outside(move |_: &nsh_core::geometry::Point<Points>| {
                outside_restore.set(false);
                outside(Event::Dismiss(id));
            })
            .on_cancel(move || emit(Event::Dismiss(id)))
            .child(children),
    )
}

pub(crate) fn popup_rectangle(value: &str) -> Result<nsh_core::geometry::Bounds<Points>, String> {
    let parts = value
        .split_whitespace()
        .map(|part| {
            part.parse::<f32>()
                .map_err(|_| "NSH anchor-rect requires decimal coordinates".to_owned())
        })
        .collect::<Result<Vec<_>, _>>()?;
    if parts.len() != 4 || parts.iter().any(|n| !n.is_finite()) {
        return Err("NSH anchor-rect exceeds native coordinates".into());
    }
    Ok(nsh_core::geometry::Bounds {
        origin: nsh_core::geometry::Point {
            x: px(parts[0]),
            y: px(parts[1]),
        },
        size: nsh_core::geometry::Size {
            width: px(parts[2]),
            height: px(parts[3]),
        },
    })
}

pub(crate) fn supported(kind: &str) -> bool {
    kind == "toast"
        || navigation::supported(kind)
        || surfaces::supported(kind)
        || basic::supported(kind)
        || collections::supported(kind)
        || matches!(
            kind,
            "button"
                | "toggle-button"
                | "toggle"
                | "switch"
                | "radio"
                | "radio-group"
                | "slider"
                | "number-stepper"
                | "progress"
                | "divider"
                | "tabs"
                | "button-group"
                | "toggle-group"
                | "toolbar"
                | "input-group"
                | "input-group-actions"
                | "menu-item"
                | "dialog"
                | "sheet"
                | "list"
                | "grid"
        )
}

/// Native Radio reports a requested check, not every activation. Do not admit
/// an activation contract until its complete public path has been qualified.
pub(crate) fn validate(node: &Node) -> Result<(), String> {
    surfaces::validate(node)?;
    collections::validate(node)?;
    basic::validate(node)?;
    if node.kind == "radio" && node.boolean("press-enabled", false) {
        return Err(
            "NSH radio press-enabled activation is not implemented yet; use on_change".into(),
        );
    }
    if node.kind == "grid" && node.number("columns", 1.0) > u16::MAX as f64 {
        return Err("NSH grid exceeds u16::MAX columns".into());
    }
    Ok(())
}

pub(crate) fn validate_transition(previous: &Node, next: &Node) -> Result<(), String> {
    collections::validate_transition(previous, next)
}

fn label(node: Signal<Arc<Node>>) -> SharedString {
    let node = node.get();
    let explicit = node.string("accessibility-label");
    if explicit.is_empty() {
        node.string("text").to_owned().into()
    } else {
        explicit.to_owned().into()
    }
}
fn enabled(node: Signal<Arc<Node>>) -> bool {
    node.get().boolean("enabled", true)
}
fn emit_flag(node: Signal<Arc<Node>>, flag: &str, emit: &Emit, event: Event) {
    let current = node.get_untracked();
    if current.boolean("enabled", true) && current.boolean(flag, false) {
        emit(event);
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
enum CommandSlot {
    Icon,
    Label,
    Children,
}

fn command_content(node: Signal<Arc<Node>>, children: AnyElement, theme: ui::Theme) -> AnyElement {
    let children = Rc::new(RefCell::new(Some(children)));
    view()
        .flex_row()
        .items_center()
        .justify_center()
        .gap(move || {
            let current = node.get();
            px(
                if current.string("text").is_empty() && current.children.is_empty() {
                    0.0
                } else {
                    8.0
                },
            )
        })
        .flex_grow(move || {
            if node.get().string("main") == "space_between" {
                1.0_f32
            } else {
                0.0_f32
            }
        })
        .state_inline_style(move || {
            let current = node.get();
            let has_content = !current.string("text").is_empty() || !current.children.is_empty();
            Style::from_decls(
                crate::style::content_layout(&current, &theme.get())
                    .expect("validated command layout")
                    .into_iter()
                    .filter(|declaration| {
                        has_content || !matches!(declaration, StyleDecl::Set(StyleKey::Gap, _))
                    }),
            )
        })
        .style_with(move |s| {
            if node.get().string("icon-placement") == "top" {
                s.flex_col()
            } else {
                s.flex_row()
            }
        })
        .child(each(
            move || {
                if node.get().string("icon-placement") == "trailing" {
                    vec![CommandSlot::Label, CommandSlot::Children, CommandSlot::Icon]
                } else {
                    vec![CommandSlot::Icon, CommandSlot::Label, CommandSlot::Children]
                }
            },
            |slot| *slot,
            move |slot, _| match slot.get_untracked() {
                CommandSlot::Icon => when(
                    move || !node.get().string("icon").is_empty(),
                    move || {
                        ui::icon(
                            move || SharedString::from(node.get().string("icon").to_owned()),
                            move || {
                                px(match node.get().string("size") {
                                    "sm" => 14.0,
                                    "lg" => 20.0,
                                    _ => 16.0,
                                })
                            },
                        )
                    },
                )
                .into_element(),
                CommandSlot::Label => when(
                    move || !node.get().string("text").is_empty(),
                    move || text(move || node.get().string("text").to_owned()),
                )
                .into_element(),
                CommandSlot::Children => children
                    .borrow_mut()
                    .take()
                    .expect("retained command children slot"),
            },
        ))
        .into_element()
}

/// Call only for an admitted supported kind; unsupported calls return None.
pub(crate) fn element(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    emit: Emit,
    presentation: Presentation,
) -> Option<AnyElement> {
    let theme = presentation.theme;
    let initial = node.get_untracked();
    if surfaces::supported(&initial.kind) {
        return surfaces::element(node, children, emit, presentation);
    }
    if basic::supported(&initial.kind) {
        return basic::element(node, children, emit, presentation);
    }
    if collections::supported(&initial.kind) {
        return collections::element(node, children, emit, presentation);
    }
    if navigation::supported(&initial.kind) {
        return navigation::element(node, children, emit, presentation);
    }
    if initial.kind == "toast" {
        return Some(toasts::element(node, children, presentation));
    }
    let id = initial.id;
    Some(match initial.kind.as_str() {
        "button" => {
            let props = ui::controls::CommandButtonProps {
                theme: Some(theme).into(),
                selected: Prop::bind(move || node.get().boolean("selected", false)),
                disabled: Prop::bind(move || !enabled(node)),
                label: Prop::bind(move || label(node)),
                variant: Prop::bind(move || node.get().string("variant").to_owned().into()),
                size: Prop::bind(move || node.get().string("size").to_owned().into()),
                ..Default::default()
            };
            presentation.component(
                ui::controls::CommandButton::element(props)
                    .on_event(move |_: &ui::controls::CommandButtonEvent| {
                        emit_flag(node, "press-enabled", &emit, Event::Press(id));
                    })
                    .child(command_content(node, children, theme)),
            )
        }
        "toggle-button" => {
            let props = nsh_base::ToggleProps {
                pressed: Prop::bind(move || node.get().boolean("selected", false)),
                disabled: Prop::bind(move || !enabled(node)),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            };
            presentation.component(
                ui::controls::command_appearance(
                    ui::controls::toggle(props, theme),
                    theme,
                    Prop::bind(move || node.get().string("variant").to_owned().into()),
                    Prop::bind(move || node.get().string("size").to_owned().into()),
                )
                .on_event(move |event: &nsh_base::ToggleEvent| {
                    if let nsh_base::ToggleEvent::Change(checked) = event {
                        emit_flag(node, "toggle-enabled", &emit, Event::Toggle(id, *checked));
                    }
                })
                .child(command_content(node, children, theme)),
            )
        }
        "toggle" => {
            let props = nsh_base::CheckboxProps {
                checked: Prop::bind(move || node.get().boolean("checked", false)),
                indeterminate: Prop::bind(move || node.get().boolean("indeterminate", false)),
                disabled: Prop::bind(move || !enabled(node)),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            };
            presentation.component(
                ui::checkbox(props, theme)
                    .on_event(move |event: &nsh_base::CheckboxEvent| {
                        let nsh_base::CheckboxEvent::Change(checked) = event;
                        emit_flag(node, "toggle-enabled", &emit, Event::Toggle(id, *checked));
                    })
                    .child(text(move || node.get().string("text").to_owned()))
                    .child(children),
            )
        }
        "switch" => {
            let props = nsh_base::SwitchProps {
                checked: Prop::bind(move || node.get().boolean("checked", false)),
                disabled: Prop::bind(move || !enabled(node)),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            };
            presentation.component(
                ui::controls::switch(props, theme)
                    .on_event(move |event: &nsh_base::SwitchEvent| {
                        let nsh_base::SwitchEvent::Change(checked) = event;
                        emit_flag(node, "toggle-enabled", &emit, Event::Toggle(id, *checked));
                    })
                    .child(text(move || node.get().string("text").to_owned()))
                    .child(children),
            )
        }
        "radio" => {
            let props = nsh_base::RadioProps {
                checked: Prop::bind(move || node.get().boolean("checked", false)),
                disabled: Prop::bind(move || !enabled(node)),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            };
            presentation.component(
                ui::controls::radio(props, theme)
                    .on_event(move |event: &nsh_base::RadioEvent| {
                        let nsh_base::RadioEvent::Change(checked) = event;
                        // Preserve LUI's existing change-before-toggle order.
                        emit_flag(node, "change-enabled", &emit, Event::Change(id));
                        emit_flag(node, "toggle-enabled", &emit, Event::Toggle(id, *checked));
                    })
                    .child(text(move || node.get().string("text").to_owned()))
                    .child(children),
            )
        }
        "radio-group" => presentation.host(
            // Keep the named host for LUI's generic event projection; native
            // RadioGroup continues to own roving keyboard navigation.
            view()
                .role(AccessibilityRole::Group)
                .label(move || label(node))
                .child(nsh_base::RadioGroup::element(Default::default()).child(children)),
        ),
        "slider" => {
            let props = nsh_base::SliderProps {
                value: Prop::bind(move || {
                    Some(nsh_base::SliderValue::Single(
                        node.get().number("value", 0.0),
                    ))
                }),
                min: 0.0.into(),
                max: 1.0.into(),
                step: 0.0.into(),
                disabled: Prop::bind(move || !enabled(node)),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            };
            presentation.component(
                ui::controls::slider(props, theme)
                    .on_event(move |event: &nsh_base::SliderEvent| {
                        if let nsh_base::SliderEvent::Change(value) = event {
                            emit_flag(node, "change-enabled", &emit, Event::Value(id, value.end()));
                        }
                    })
                    .child(children),
            )
        }
        "number-stepper" => {
            let props = nsh_base::NumberInputProps {
                value: Prop::bind(move || Some(node.get().number("value", 0.0))),
                min: Prop::bind(move || Some(node.get().number("min", 0.0))),
                max: Prop::bind(move || {
                    node.get()
                        .props
                        .get("max")
                        .and_then(serde_json::Value::as_f64)
                }),
                step: Prop::bind(move || node.get().number("step", 1.0)),
                disabled: Prop::bind(move || !enabled(node)),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            };
            presentation.component(ui::controls::number_input(props, theme).on_event(
                move |event: &nsh_base::NumberInputEvent| {
                    if let nsh_base::NumberInputEvent::Change(Some(value)) = event {
                        emit_flag(node, "change-enabled", &emit, Event::Value(id, *value));
                    }
                },
            ))
        }
        "progress" => presentation.component(ui::controls::progress(
            nsh_base::ProgressProps {
                value: Prop::bind(move || (node.get().number("value", 0.0) * 100.0) as f32),
                ..Default::default()
            },
            theme,
        )),
        "tabs" => presentation.component(
            ui::controls::Tabs::element(ui::controls::TabsProps {
                theme: Some(theme).into(),
                vertical: Prop::bind(move || node.get().string("orientation") == "vertical"),
                label: Prop::bind(move || label(node)),
                gap: Prop::bind(move || px(node.get().number("gap", 0.0) as f32)),
                ..Default::default()
            })
            .child(children),
        ),
        "toggle-group" => presentation.component(
            nsh_base::ToggleGroup::element(Default::default())
                .flex_row()
                .child(children),
        ),
        "button-group" => presentation.component(
            nsh_base::ToolbarGroup::element(nsh_base::ToolbarGroupProps {
                accessibility_label: Prop::bind(move || {
                    let label = label(node);
                    (!label.is_empty()).then_some(label)
                }),
                ..Default::default()
            })
            .flex_row()
            .child(children),
        ),
        "toolbar" => presentation.component(
            nsh_base::Toolbar::element(nsh_base::ToolbarProps {
                axis: if initial.string("orientation") == "vertical" {
                    Axis::Vertical
                } else {
                    Axis::Horizontal
                }
                .into(),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            })
            .child(children),
        ),
        "menu-item" => {
            let props = nsh_base::MenuItemProps {
                disabled: Prop::bind(move || !enabled(node)),
                checked: Prop::bind(move || {
                    let node = node.get();
                    node.props
                        .contains_key("selected")
                        .then(|| node.boolean("selected", false))
                }),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            };
            presentation.component(
                ui::controls::menu_item(props, theme)
                    .on_event(move |_: &nsh_base::MenuItemEvent| {
                        emit_flag(node, "press-enabled", &emit, Event::Press(id))
                    })
                    .child(text(move || node.get().string("text").to_owned()))
                    .child(children),
            )
        }
        "dialog" => {
            let dismiss = emit;
            let style = presentation.style.clone();
            presentation.host_identity(
                nsh_base::dialog()
                    .flex_1()
                    .items_center()
                    .justify_center()
                    .label(move || node.get().string("text").to_owned())
                    .accessibility_description(move || node.get().string("description").to_owned())
                    .close_on_escape(false)
                    .close_on_backdrop_press(false)
                    .on_cancel(move || dismiss(Event::Dismiss(id)))
                    .child(
                        ui::controls::panel(theme)
                            .min_w_64()
                            .state_inline_style(move || style())
                            .child(
                                text(move || node.get().string("text").to_owned())
                                    .text_lg()
                                    .font_weight(FontWeight::SEMIBOLD),
                            )
                            .child(text(move || node.get().string("description").to_owned()))
                            .child(children),
                    ),
            )
        }
        "sheet" => {
            let style = presentation.style.clone();
            presentation.component_identity(
                nsh_base::Sheet::element(nsh_base::SheetProps {
                    open: Some(true).into(),
                    popup_class: Some("p-4 gap-3 border".into()).into(),
                    popup_style: Prop::bind(move || {
                        ui::part(
                            StyleRefinement::default()
                                .bg(ui::color(theme, "popover"))
                                .text_color(ui::color(theme, "popover-foreground"))
                                .border_color(ui::color(theme, "border"))
                                .rounded(ui::radius(theme)),
                        )
                        .then(&style())
                    }),
                    backdrop_class: Some("bg-background/60".into()).into(),
                    backdrop_style: Prop::bind(move || {
                        ui::part(
                            StyleRefinement::default()
                                .bg(ui::color(theme, "background").opacity(0.6)),
                        )
                    }),
                    ..Default::default()
                })
                .on_event(move |event: &nsh_base::SheetEvent| {
                    if matches!(event, nsh_base::SheetEvent::Cancel) {
                        emit(Event::Dismiss(id));
                    }
                })
                .child(
                    text(move || node.get().string("text").to_owned())
                        .text_lg()
                        .font_weight(FontWeight::SEMIBOLD),
                )
                .child(children),
            )
        }
        "list" => presentation.host(scroll().role(AccessibilityRole::List).child(children)),
        "grid" => presentation.host(
            view()
                .grid()
                .grid_cols(move || {
                    node.get()
                        .number("columns", 1.0)
                        .clamp(1.0, u16::MAX as f64) as u16
                })
                .child(children),
        ),
        "divider" => presentation.host(
            view()
                .accessibility_elements_hidden(true)
                .bg(move || ui::color(theme, "border"))
                .style_with(move |s| {
                    if node.get().string("orientation") == "vertical" {
                        s.w(px(1.0)).h_full()
                    } else {
                        s.h(px(1.0)).w_full()
                    }
                }),
        ),
        "input-group" => presentation.host(
            view()
                .role(AccessibilityRole::Group)
                .border_1()
                .border_color(move || ui::color(theme, "border"))
                .rounded(move || ui::radius(theme))
                .child(children),
        ),
        "input-group-actions" => {
            presentation.host(view().flex_row().items_center().gap_2().child(children))
        }
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_core::platform::Os;
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use serde_json::{Map, Value, json};
    use std::sync::Mutex;

    struct Fixture {
        kind: String,
        props: Map<String, Value>,
        follow: bool,
        events: Arc<Mutex<Vec<Event>>>,
    }

    fn presentation(id: u64) -> Presentation {
        Presentation {
            key: format!("node-{id}").into(),
            test_id: format!("control-{id}").into(),
            style: Rc::new(Style::default),
            reference: element_ref(),
            theme: signal(Arc::new(crate::style::ThemeView::new(
                tokens(),
                dark(),
                reduce_motion(),
            ))),
            events: None,
            children: None,
        }
    }

    #[component]
    fn SingleControl() -> impl IntoElement {
        let fixture = engine_context::<Fixture>().unwrap();
        let authored_child = fixture.kind == "button" && fixture.follow;
        let grouped_command = fixture.kind == "button-group";
        let node = signal(Arc::new(Node {
            id: 1,
            incarnation: 1,
            kind: fixture.kind.clone(),
            props: fixture.props.clone(),
            children: Arc::new(if authored_child || grouped_command {
                vec![2]
            } else {
                Vec::new()
            }),
            ..Default::default()
        }));
        let shown = signal(true);
        let emit: Emit = Rc::new(move |event| {
            fixture.events.lock().unwrap().push(event.clone());
            if !fixture.follow {
                return;
            }
            let mut next = (*node.get_untracked()).clone();
            match event {
                Event::Press(_) if next.kind == "button" => {
                    if next.props.contains_key("gap") {
                        next.props.insert("gap".into(), json!(20));
                    }
                    next.props.insert("icon".into(), json!("check"));
                    next.props.insert("size".into(), json!("lg"));
                    next.props.insert("variant".into(), json!("destructive"));
                    next.props
                        .insert("icon-placement".into(), json!("trailing"));
                }
                Event::Toggle(_, value) => {
                    let property = if next.kind == "toggle-button" {
                        "selected"
                    } else {
                        "checked"
                    };
                    next.props.insert(property.into(), json!(value));
                }
                Event::Value(_, value) => {
                    next.props.insert("value".into(), json!(value));
                }
                Event::Dismiss(_) => shown.set(false),
                _ => {}
            }
            node.set(Arc::new(next));
        });
        view()
            .w_64()
            .child(when(shown, move || {
                let children = if authored_child {
                    let child = view()
                        .test_id("authored-command-child")
                        .child(text("Details"));
                    if node.get_untracked().props.contains_key("cross") {
                        child.h(px(80.0)).into_element()
                    } else {
                        child.into_element()
                    }
                } else if grouped_command {
                    nsh_base::Button::element(Default::default())
                        .child(text("Undo"))
                        .into_element()
                } else {
                    when(false, view).into_element()
                };
                let mut authored = presentation(1);
                if node.get_untracked().kind == "button" {
                    let theme = authored.theme;
                    authored.style = Rc::new(move || {
                        crate::style::compile(
                            &node.get(),
                            &theme.get(),
                            nsh_core::geometry::Size::default(),
                        )
                        .expect("valid authored command style")
                    });
                }
                element(node, children, emit.clone(), authored).unwrap()
            }))
            .child(text(move || format!("model:{:?}", node.get().props)))
    }

    fn start(kind: &str, properties: Value, follow: bool) -> (Headless, Arc<Mutex<Vec<Event>>>) {
        let events = Arc::new(Mutex::new(Vec::new()));
        let mut config = EngineConfig {
            context: EngineContext::default().with(Fixture {
                kind: kind.into(),
                props: properties.as_object().unwrap().clone(),
                follow,
                events: events.clone(),
            }),
            ..EngineConfig::new(Root::of::<SingleControl>())
        };
        config.environment.os = Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        (app, events)
    }

    #[test]
    fn switch_follows_accepted_press_and_keyboard_values_without_duplicate_events() {
        let (mut app, seen) = start(
            "switch",
            json!({"text":"Enabled","checked":false,"toggle-enabled":true}),
            true,
        );
        app.press("role:switch[Enabled]").unwrap();
        assert_eq!(
            app.screen()
                .accessibility_state("role:switch[Enabled]")
                .unwrap()
                .checked,
            Some(nsh_core::Checked::True)
        );
        app.press_key("tab").unwrap();
        app.press_key("space").unwrap();
        assert_eq!(
            app.screen()
                .accessibility_state("role:switch[Enabled]")
                .unwrap()
                .checked,
            Some(nsh_core::Checked::False)
        );
        assert_eq!(
            *seen.lock().unwrap(),
            [Event::Toggle(1, true), Event::Toggle(1, false)]
        );
    }

    #[test]
    fn refused_switch_requests_keep_native_identity_and_accepted_value() {
        let (mut app, seen) = start(
            "switch",
            json!({"text":"Enabled","checked":false,"toggle-enabled":true}),
            false,
        );
        let identity = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("control-1"))
            .unwrap()
            .id;
        app.press("role:switch[Enabled]").unwrap();
        app.press("role:switch[Enabled]").unwrap();
        assert_eq!(
            app.screen()
                .accessibility_state("role:switch[Enabled]")
                .unwrap()
                .checked,
            Some(nsh_core::Checked::False)
        );
        assert_eq!(
            *seen.lock().unwrap(),
            [Event::Toggle(1, true), Event::Toggle(1, true)]
        );
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|n| n.test_id.as_deref() == Some("control-1"))
                .unwrap()
                .id,
            identity
        );
    }

    #[test]
    fn disabled_switch_takes_no_user_event() {
        let (mut app, seen) = start(
            "switch",
            json!({"text":"Enabled","checked":false,"toggle-enabled":true,"enabled":false}),
            true,
        );
        let _ = app.press("id:control-1");
        assert!(seen.lock().unwrap().is_empty());
        assert!(
            app.screen()
                .accessibility_state("id:control-1")
                .unwrap()
                .disabled
        );
    }

    #[test]
    fn button_group_passes_its_authored_name_to_the_native_toolbar_group() {
        let (app, _) = start(
            "button-group",
            json!({"accessibility-label":"History"}),
            false,
        );
        assert_eq!(app.screen().count("role:group[History]").unwrap(), 1);
    }

    #[test]
    fn toggle_button_exposes_pressed_semantics_and_uses_selected_as_value() {
        let (mut app, seen) = start(
            "toggle-button",
            json!({"text":"Bold","selected":false,"toggle-enabled":true}),
            true,
        );
        app.press("role:button[Bold]").unwrap();
        assert_eq!(
            app.screen()
                .accessibility_state("role:button[Bold]")
                .unwrap()
                .pressed,
            Some(nsh_core::Checked::True)
        );
        assert_eq!(*seen.lock().unwrap(), [Event::Toggle(1, true)]);
    }

    #[test]
    fn authored_command_icon_size_and_variant_update_without_remounting() {
        let (mut app, seen) = start(
            "button",
            json!({"text":"Save","icon":"plus","size":"sm","variant":"ghost","press-enabled":true}),
            true,
        );
        let control = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("control-1"))
            .unwrap();
        let icon = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.kind == nsh_core::ViewKind::Canvas)
            .unwrap();
        assert_eq!(icon.bounds.size.width, px(14.0));
        let child = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("authored-command-child"))
            .unwrap();
        let before = app
            .screen()
            .span_style("id:control-1 >> text:Save")
            .unwrap()
            .color;
        app.press("role:button[Save]").unwrap();
        let next_control = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("control-1"))
            .unwrap();
        let next_icon = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.kind == nsh_core::ViewKind::Canvas)
            .unwrap();
        let label = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.text.as_ref().is_some_and(|t| t.text.text == "Save"))
            .unwrap();
        let next_child = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("authored-command-child"))
            .unwrap();
        assert_eq!(next_control.id, control.id);
        assert_eq!(next_icon.id, icon.id);
        assert_eq!(next_child.id, child.id);
        assert_eq!(next_icon.bounds.size.width, px(20.0));
        assert!(next_control.bounds.size.height > control.bounds.size.height);
        assert!(next_icon.bounds.origin.x > label.bounds.origin.x);
        assert!(next_child.bounds.origin.x > label.bounds.origin.x);
        assert!(
            next_icon.bounds.origin.x >= next_child.bounds.origin.x + next_child.bounds.size.width
        );
        assert_ne!(
            app.screen()
                .span_style("id:control-1 >> text:Save")
                .unwrap()
                .color,
            before
        );
        assert_eq!(*seen.lock().unwrap(), [Event::Press(1)]);
    }

    #[test]
    fn authored_command_gap_updates_icon_and_child_spacing_without_remounting() {
        let (mut app, _) = start(
            "button",
            json!({"text":"Save","icon":"plus","gap":0,"press-enabled":true}),
            true,
        );
        let layout = |app: &Headless| {
            let nodes = app.screen().layout_nodes();
            let icon = nodes
                .iter()
                .find(|node| node.kind == nsh_core::ViewKind::Canvas)
                .unwrap()
                .clone();
            let label = nodes
                .iter()
                .find(|node| {
                    node.text
                        .as_ref()
                        .is_some_and(|text| text.text.text == "Save")
                })
                .unwrap()
                .clone();
            let child = nodes
                .iter()
                .find(|node| node.test_id.as_deref() == Some("authored-command-child"))
                .unwrap()
                .clone();
            (icon, label, child)
        };
        let (icon, label, child) = layout(&app);
        assert_eq!(
            label.bounds.origin.x,
            icon.bounds.origin.x + icon.bounds.size.width
        );
        assert_eq!(
            child.bounds.origin.x,
            label.bounds.origin.x + label.bounds.size.width
        );
        app.press("id:control-1").unwrap();
        let (next_icon, next_label, next_child) = layout(&app);
        assert_eq!(
            (next_icon.id, next_label.id, next_child.id),
            (icon.id, label.id, child.id)
        );
        assert_eq!(
            next_child.bounds.origin.x - next_label.bounds.origin.x - next_label.bounds.size.width,
            px(20.0)
        );
        assert_eq!(
            next_icon.bounds.origin.x - next_child.bounds.origin.x - next_child.bounds.size.width,
            px(20.0)
        );
    }

    #[test]
    fn authored_command_alignment_distributes_slots_and_preserves_reordered_children() {
        let (mut app, _) = start(
            "button",
            json!({"text":"Save","icon":"plus","width":220,"height":120,"main":"space_between","cross":"end","press-enabled":true}),
            true,
        );
        let layout = |app: &Headless| {
            let nodes = app.screen().layout_nodes();
            let icon = nodes
                .iter()
                .find(|node| node.kind == nsh_core::ViewKind::Canvas)
                .unwrap()
                .clone();
            let label = nodes
                .iter()
                .find(|node| {
                    node.text
                        .as_ref()
                        .is_some_and(|text| text.text.text == "Save")
                })
                .unwrap()
                .clone();
            let child = nodes
                .iter()
                .find(|node| node.test_id.as_deref() == Some("authored-command-child"))
                .unwrap()
                .clone();
            (icon, label, child)
        };
        let close = |a: Points, b: Points| assert!((a.0 - b.0).abs() < 0.01, "{a:?} != {b:?}");
        // NSH rounds absolute edges to device pixels. At the headless 1x
        // scale an odd free pixel belongs to one of the two equal gaps.
        let balanced = |a: Points, b: Points| assert!((a.0 - b.0).abs() <= 1.0, "{a:?} != {b:?}");
        let (icon, label, child) = layout(&app);
        let first_gap = label.bounds.origin.x - icon.bounds.origin.x - icon.bounds.size.width;
        let second_gap = child.bounds.origin.x - label.bounds.origin.x - label.bounds.size.width;
        assert!(first_gap > px(8.0));
        balanced(first_gap, second_gap);
        let control = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("control-1"))
            .unwrap();
        close(icon.bounds.origin.x, control.bounds.origin.x + px(12.0));
        close(
            child.bounds.origin.x + child.bounds.size.width,
            control.bounds.origin.x + control.bounds.size.width - px(12.0),
        );
        close(
            icon.bounds.origin.y + icon.bounds.size.height,
            child.bounds.origin.y + child.bounds.size.height,
        );
        close(
            label.bounds.origin.y + label.bounds.size.height,
            child.bounds.origin.y + child.bounds.size.height,
        );
        app.press("id:control-1").unwrap();
        let (next_icon, next_label, next_child) = layout(&app);
        assert_eq!(
            (next_icon.id, next_label.id, next_child.id),
            (icon.id, label.id, child.id)
        );
        assert!(next_label.bounds.origin.x < next_child.bounds.origin.x);
        assert!(next_child.bounds.origin.x < next_icon.bounds.origin.x);
        balanced(
            next_child.bounds.origin.x - next_label.bounds.origin.x - next_label.bounds.size.width,
            next_icon.bounds.origin.x - next_child.bounds.origin.x - next_child.bounds.size.width,
        );
        close(
            next_icon.bounds.origin.y + next_icon.bounds.size.height,
            next_child.bounds.origin.y + next_child.bounds.size.height,
        );
    }

    #[test]
    fn icon_only_command_has_square_geometry_and_named_keyboard_activation() {
        let (mut app, seen) = start(
            "button",
            json!({"icon":"plus","size":"icon","accessibility-label":"Add item","press-enabled":true}),
            false,
        );
        let control = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("control-1"))
            .unwrap();
        assert_eq!(control.bounds.size.width, px(32.0));
        assert_eq!(control.bounds.size.height, px(32.0));
        let icon = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.kind == nsh_core::ViewKind::Canvas)
            .unwrap();
        assert_eq!(
            icon.bounds.origin.x + icon.bounds.size.width / 2.0,
            control.bounds.origin.x + control.bounds.size.width / 2.0
        );
        assert_eq!(
            icon.bounds.origin.y + icon.bounds.size.height / 2.0,
            control.bounds.origin.y + control.bounds.size.height / 2.0
        );
        app.press_key("tab").unwrap();
        app.press_key("enter").unwrap();
        assert_eq!(*seen.lock().unwrap(), [Event::Press(1)]);
    }

    #[test]
    fn radio_reports_change_before_toggle_and_cannot_uncheck_itself() {
        let (mut app, seen) = start(
            "radio",
            json!({"text":"Compact","checked":false,"change-enabled":true,"toggle-enabled":true}),
            true,
        );
        app.press("role:radio[Compact]").unwrap();
        app.press_key("space").unwrap();
        assert_eq!(
            *seen.lock().unwrap(),
            [Event::Change(1), Event::Toggle(1, true)]
        );
        assert_eq!(
            app.screen()
                .accessibility_state("role:radio[Compact]")
                .unwrap()
                .checked,
            Some(nsh_core::Checked::True)
        );
    }

    #[test]
    fn slider_uses_unit_interval_and_reports_one_value_per_keyboard_step() {
        let (mut app, seen) = start(
            "slider",
            json!({"accessibility-label":"Volume","value":0.5,"change-enabled":true}),
            true,
        );
        app.press_key("tab").unwrap();
        app.press_key("right").unwrap();
        let events = seen.lock().unwrap();
        assert_eq!(events.len(), 1);
        let Event::Value(1, value) = events[0] else {
            panic!("not a value event")
        };
        assert!(value > 0.5 && value < 0.6, "{value}");
    }

    #[test]
    fn number_stepper_does_not_impose_an_unrequested_100_limit() {
        let (mut app, seen) = start(
            "number-stepper",
            json!({"accessibility-label":"Count","text":"Count","value":200.0,"change-enabled":true}),
            true,
        );
        app.press_key("tab").unwrap();
        app.press_key("up").unwrap();
        assert_eq!(*seen.lock().unwrap(), [Event::Value(1, 201.0)]);
        assert_eq!(
            app.screen().input_text("role:spinbutton[Count]").unwrap(),
            Some("201")
        );
    }

    #[test]
    fn progress_unit_fraction_fills_half_its_native_track() {
        let (app, _) = start("progress", json!({"value":0.5}), true);
        assert_eq!(app.screen().count("role:progressbar").unwrap(), 1);
        let nodes = app.screen().layout_nodes();
        let root = nodes
            .iter()
            .find(|n| n.test_id.as_deref() == Some("control-1"))
            .unwrap();
        let track = nodes.iter().find(|n| n.parent == root.id).unwrap();
        let indicator = nodes.iter().find(|n| n.parent == track.id).unwrap();
        assert!((indicator.bounds.size.width.0 / track.bounds.size.width.0 - 0.5).abs() < 0.001);
    }

    #[test]
    fn dialog_escape_requests_application_owned_dismissal_once() {
        let (mut app, seen) = start(
            "dialog",
            json!({"text":"Confirm","description":"Review the change"}),
            true,
        );
        app.wait_for("role:dialog[Confirm]").unwrap();
        app.press_key("escape").unwrap();
        app.wait_until(
            "dialog dismissal",
            std::time::Duration::from_secs(2),
            |screen| screen.count("role:dialog[Confirm]") == Ok(0),
        )
        .unwrap();
        assert_eq!(*seen.lock().unwrap(), [Event::Dismiss(1)]);
    }

    #[component]
    fn GroupedChoices() -> impl IntoElement {
        let fixture = engine_context::<Fixture>().unwrap();
        let tabs = fixture.kind == "tabs";
        let root = signal(Arc::new(Node {
            id: 1,
            incarnation: 1,
            kind: fixture.kind.clone(),
            props: json!({"accessibility-label":"Density"})
                .as_object()
                .unwrap()
                .clone(),
            ..Default::default()
        }));
        let sources = Rc::new(
            ["One", "Two", "Three"]
                .into_iter()
                .enumerate()
                .map(|(index, text)| {
                    signal(Arc::new(Node {
                        id: index as u64 + 2,
                        incarnation: 1,
                        kind: if tabs { "button" } else { "radio" }.into(),
                        props: json!({"text":text,"enabled": index != 1,"selected":index == 0,
                              "checked":index == 0,"press-enabled":tabs,
                              "change-enabled":!tabs,"toggle-enabled":!tabs})
                        .as_object()
                        .unwrap()
                        .clone(),
                        ..Default::default()
                    }))
                })
                .collect::<Vec<_>>(),
        );
        let updated = sources.clone();
        let emit: Emit = Rc::new(move |event| {
            fixture.events.lock().unwrap().push(event.clone());
            let selected = match event {
                Event::Press(id) if tabs => Some(id),
                Event::Toggle(id, true) if !tabs => Some(id),
                _ => None,
            };
            if let Some(selected) = selected {
                batch(|| {
                    for source in updated.iter() {
                        let mut next = (*source.get_untracked()).clone();
                        next.props.insert(
                            if tabs { "selected" } else { "checked" }.into(),
                            json!(next.id == selected),
                        );
                        source.set(Arc::new(next));
                    }
                });
            }
        });
        let child_emit = emit.clone();
        let children = each(
            signal(vec![0_usize, 1, 2]),
            |index| *index,
            move |index, _| {
                let index = index.get_untracked();
                element(
                    sources[index],
                    view().into_element(),
                    child_emit.clone(),
                    presentation(index as u64 + 2),
                )
                .unwrap()
            },
        );
        view()
            .w_64()
            .child(element(root, children.into_element(), emit, presentation(1)).unwrap())
    }

    fn grouped(kind: &str) -> (Headless, Arc<Mutex<Vec<Event>>>) {
        let events = Arc::new(Mutex::new(Vec::new()));
        let mut config = EngineConfig {
            context: EngineContext::default().with(Fixture {
                kind: kind.into(),
                props: Map::new(),
                follow: true,
                events: events.clone(),
            }),
            ..EngineConfig::new(Root::of::<GroupedChoices>())
        };
        config.environment.os = Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        (app, events)
    }

    #[test]
    fn tabs_convert_lui_buttons_and_use_native_arrow_navigation() {
        let (mut app, events) = grouped("tabs");
        assert_eq!(app.screen().count("role:group[Density]").unwrap(), 1);
        assert_eq!(app.screen().count("role:tab[One]").unwrap(), 1);
        app.press_key("tab").unwrap();
        app.press_key("right").unwrap();
        assert_eq!(*events.lock().unwrap(), [Event::Press(4)]);
        assert!(
            app.screen()
                .accessibility_state("role:tab[Three]")
                .unwrap()
                .selected
        );
    }

    #[test]
    fn radio_group_preserves_its_name_and_native_arrows_skip_disabled_choices() {
        let (mut app, events) = grouped("radio-group");
        assert_eq!(app.screen().count("role:group[Density]").unwrap(), 1);
        app.press_key("tab").unwrap();
        app.press_key("right").unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            [Event::Change(4), Event::Toggle(4, true)]
        );
        assert_eq!(
            app.screen()
                .accessibility_state("role:radio[Three]")
                .unwrap()
                .checked,
            Some(nsh_core::Checked::True)
        );
    }

    #[test]
    fn unsupported_activation_contracts_fail_before_mounting() {
        let node = Node {
            kind: "radio".into(),
            props: json!({"press-enabled":true}).as_object().unwrap().clone(),
            ..Default::default()
        };
        assert!(validate(&node).is_err());
    }
}
