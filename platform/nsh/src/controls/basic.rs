//! Basic retained presentation and local layered layout.
use super::{ChildRenderer, Emit, Presentation, emit_flag, enabled, label};
use crate::{render::Event, store::Node, ui};
use nsh_core::{
    StyleDecl, StyleKey, StyleValue,
    element::{ImageSrc, Style, StyleRefinement, View},
    prelude::*,
};
use std::{cell::RefCell, rc::Rc, sync::Arc};

pub(super) fn supported(kind: &str) -> bool {
    matches!(
        kind,
        "stack"
            | "edge-inset"
            | "overlay"
            | "alert"
            | "bubble"
            | "spinner"
            | "icon"
            | "avatar"
            | "status-bar"
            | "link"
    )
}

pub(super) fn validate(node: &Node) -> Result<(), String> {
    if node.kind == "edge-inset" {
        if node.children.len() > 32_760 {
            return Err("NSH edge-inset exceeds native grid line capacity".into());
        }
        if node.props.keys().any(|name| {
            ["hover-", "pressed-", "focus-", "selected-", "disabled-"]
                .iter()
                .any(|prefix| name.starts_with(prefix))
        }) {
            return Err("NSH edge-inset pooled state paint is not implemented yet".into());
        }
        if node
            .props
            .get("opacity")
            .is_some_and(|value| value.as_f64() != Some(1.0))
            || node.props.contains_key("transition")
            || (!node.string("shadow").is_empty() && node.string("shadow") != "none")
        {
            return Err(
                "NSH edge-inset pooled opacity, shadow and transitions are not implemented yet"
                    .into(),
            );
        }
    }
    if node.kind == "avatar" && node.props.contains_key("image") {
        return Err("NSH avatar image resources require the native image-resource bridge".into());
    }
    if node.kind == "link"
        && !node.boolean("press-enabled", false)
        && !node.string("url").is_empty()
    {
        nsh_core::open_url::check_url(node.string("url")).map_err(|error| {
            format!("NSH system link requires an external URL or a press handler: {error}")
        })?;
    }
    Ok(())
}

fn extent(node: &Node, spinner: bool) -> Points {
    px(match (node.string("size"), spinner) {
        ("sm", _) => 16.0,
        ("lg", _) => 24.0,
        (_, true) => 20.0,
        _ => 18.0,
    })
}

fn grid_cell() -> Style {
    Style::from_decls([StyleKey::GridColumn, StyleKey::GridRow].map(|key| {
        StyleDecl::Set(
            key,
            key.parse_value(StyleValue::Str("1 / 2"))
                .expect("fixed grid cell"),
        )
    }))
}

fn layered(children: ChildRenderer) -> View {
    let render = children.render;
    let lookup = children.lookup;
    view().grid().grid_cols(1).grid_rows(1).child(each(
        children.identities,
        |identity| *identity,
        move |identity, _| {
            let identity = identity.get_untracked();
            let node = (lookup)(identity);
            // Preserve the child's grid-item stretch through this z-index layer.
            view()
                .grid()
                .grid_cols(1)
                .grid_rows(1)
                .pointer_events(nsh_core::PointerEvents::BoxNone)
                .inline_style(grid_cell())
                .z_index(move || {
                    node.map_or(0, |node| {
                        crate::style::z_index(&node.get())
                            .expect("validated layer z-index")
                            .unwrap_or(0)
                    })
                })
                .child((render)(identity))
        },
    ))
}

fn surface(node: Signal<Arc<Node>>, theme: ui::Theme) -> View {
    view()
        .flex_col()
        .gap_2()
        .p_4()
        .rounded(move || ui::radius(theme))
        .style_with(move |s| {
            let node = node.get();
            let variant = node.string("variant");
            let (background, foreground, border, tint) = match variant {
                "primary" => ("primary", "card-foreground", "primary", true),
                "destructive" => ("destructive", "destructive", "destructive", true),
                _ => ("card", "card-foreground", "border", false),
            };
            let s = s.text_color(ui::color(theme, foreground));
            if variant == "ghost" {
                s.bg(ui::color(theme, background).opacity(0.0))
                    .border(px(0.0))
            } else {
                s.bg(ui::color(theme, background).opacity(if tint { 0.1 } else { 1.0 }))
                    .border_1()
                    .border_color(ui::color(theme, border).opacity(if tint { 0.4 } else { 1.0 }))
            }
        })
}

fn tooltip(node: Signal<Arc<Node>>, theme: ui::Theme) -> impl nsh_core::element::IntoTooltip {
    nsh_base::tooltip()
        .disabled(move || {
            node.get().string("tooltip").is_empty() && node.get().string("tooltip-keys").is_empty()
        })
        .child(
            ui::controls::panel(theme)
                .px_2()
                .py_1()
                .child(text(move || {
                    let node = node.get();
                    match (node.string("tooltip"), node.string("tooltip-keys")) {
                        (text, "") => text.to_owned(),
                        ("", keys) => keys.to_owned(),
                        (text, keys) => format!("{text} ({keys})"),
                    }
                })),
        )
}

#[derive(Clone, PartialEq)]
struct InsetGeometry {
    count: usize,
    edge: String,
    visible: bool,
    insets: [Points; 4],
    gap: Points,
    rtl: bool,
}

#[derive(Clone, Copy, PartialEq)]
struct GridCell {
    rows: [usize; 2],
    columns: [usize; 2],
}
impl GridCell {
    fn style(self) -> Style {
        Style::from_decls(
            [
                (StyleKey::GridRow, self.rows),
                (StyleKey::GridColumn, self.columns),
            ]
            .map(|(key, range)| {
                let text = format!("{} / {}", range[0], range[1]);
                StyleDecl::Set(
                    key,
                    key.parse_value(StyleValue::Str(&text))
                        .expect("bounded edge-inset grid lines"),
                )
            }),
        )
    }
}

#[derive(PartialEq)]
struct InsetPlan {
    geometry: InsetGeometry,
    rows: SharedString,
    columns: SharedString,
    side: bool,
    main_track: usize,
    pin_start: usize,
    decoration: GridCell,
}
impl InsetPlan {
    fn new(geometry: InsetGeometry) -> Self {
        let side = matches!(geometry.edge.as_str(), "leading" | "trailing");
        let pins = geometry.count.saturating_sub(1);
        if pins == 0 {
            return Self {
                geometry,
                rows: "minmax(0, 1fr)".into(),
                columns: "minmax(0, 1fr)".into(),
                side,
                main_track: 1,
                pin_start: 1,
                decoration: GridCell {
                    rows: [1, 2],
                    columns: [1, 2],
                },
            };
        }
        let [top, right, bottom, left] = geometry.insets;
        let (before, after, cross_before, cross_after) = if side {
            let (before, after) = if geometry.rtl {
                (right, left)
            } else {
                (left, right)
            };
            (before, after, top, bottom)
        } else {
            let (cross_before, cross_after) = if geometry.rtl {
                (right, left)
            } else {
                (left, right)
            };
            (top, bottom, cross_before, cross_after)
        };
        let point = |value: Points| format!("{}px", if geometry.visible { value.0 } else { 0.0 });
        let content_first = matches!(geometry.edge.as_str(), "bottom" | "trailing");
        let mut tracks = Vec::with_capacity(pins + 4);
        if content_first {
            tracks.push("minmax(0, 1fr)".to_owned());
            tracks.push(point(geometry.gap));
        }
        let decoration_start = tracks.len() + 1;
        tracks.push(point(before));
        let pin_start = tracks.len() + 1;
        tracks.extend(std::iter::repeat_n("auto".to_owned(), pins));
        tracks.push(point(after));
        let decoration_end = tracks.len() + 1;
        let main_track = if content_first {
            1
        } else {
            tracks.push(point(geometry.gap));
            tracks.len() + 1
        };
        if !content_first {
            tracks.push("minmax(0, 1fr)".to_owned());
        }
        let along: SharedString = tracks.join(" ").into();
        let cross: SharedString = format!(
            "{} minmax(0, 1fr) {}",
            point(cross_before),
            point(cross_after)
        )
        .into();
        let (rows, columns, decoration) = if side {
            (
                cross,
                along,
                GridCell {
                    rows: [1, 4],
                    columns: [decoration_start, decoration_end],
                },
            )
        } else {
            (
                along,
                cross,
                GridCell {
                    rows: [decoration_start, decoration_end],
                    columns: [1, 4],
                },
            )
        };
        Self {
            geometry,
            rows,
            columns,
            side,
            main_track,
            pin_start,
            decoration,
        }
    }
    fn cell(&self, index: usize) -> GridCell {
        if self.geometry.count < 2 {
            return GridCell {
                rows: [1, 2],
                columns: [1, 2],
            };
        }
        let (along, cross) = if index == 0 {
            ([self.main_track, self.main_track + 1], [1, 4])
        } else {
            let at = self.pin_start + index - 1;
            ([at, at + 1], [2, 3])
        };
        if self.side {
            GridCell {
                rows: cross,
                columns: along,
            }
        } else {
            GridCell {
                rows: along,
                columns: cross,
            }
        }
    }
}

fn edge_inset(
    node: Signal<Arc<Node>>,
    children: ChildRenderer,
    presentation: Presentation,
) -> AnyElement {
    let theme = presentation.theme;
    let authored = presentation.style.clone();
    let styles = computed(move || {
        crate::style::edge_inset_styles(&node.get(), &theme.get(), &authored())
            .expect("validated edge-inset parts")
    });
    let identities = children.identities;
    let geometry = computed(move || {
        let node = node.get();
        let styles = styles.get();
        InsetGeometry {
            count: identities.with(Vec::len),
            edge: node.string("edge").to_owned(),
            visible: node.boolean("visible", true),
            insets: styles.insets,
            gap: styles.gap,
            // The same public, doc-hidden environment read NSH base controls use.
            rtl: nsh_core::element::layout_rtl(),
        }
    });
    let plan = computed(move || Arc::new(InsetPlan::new(geometry.get())));
    let decoration = view()
        .test_id(&format!("lui-inset-decoration-{}", node.get_untracked().id))
        .pointer_events(nsh_core::PointerEvents::None)
        .accessibility_elements_hidden(true)
        .z_index(i32::MIN)
        .style_when(
            move || !plan.get().geometry.visible || plan.get().geometry.count < 2,
            |s| s.hidden(),
        )
        .state_inline_style(move || plan.get().decoration.style().then(&styles.get().decoration));
    let render = children.render;
    let body = each(
        identities,
        |identity| *identity,
        move |identity, index| {
            let identity = identity.get_untracked();
            crate::events::scope_visibility(move || {
                index.get() == 0 || plan.get().geometry.visible
            });
            view()
                .min_w(px(0.0))
                .min_h(px(0.0))
                .style_with(move |s| {
                    let plan = plan.get();
                    let s = if plan.side && index.get() > 0 {
                        s.flex_row()
                    } else {
                        s.flex_col()
                    };
                    if index.get() > 0 && !plan.geometry.visible {
                        s.hidden()
                    } else {
                        s
                    }
                })
                .state_inline_style(move || {
                    let plan = plan.get();
                    let index = index.get();
                    let current = node.get();
                    let mut placement = plan.cell(index).style();
                    let axis = if plan.side {
                        StyleKey::AlignSelf
                    } else {
                        StyleKey::JustifySelf
                    };
                    let cross = if index == 0 {
                        let cross = current.string("cross");
                        if cross.is_empty() { "stretch" } else { cross }
                    } else {
                        "stretch"
                    };
                    placement = placement.with(
                        axis,
                        axis.parse_value(StyleValue::Str(cross))
                            .expect("validated edge-inset cross alignment"),
                    );
                    if index > 0 {
                        placement.then(&styles.get().inherited)
                    } else {
                        placement
                    }
                })
                .child(render(identity))
        },
    );
    let host = view()
        .grid()
        .items_stretch()
        .grid_template_rows(move || plan.get().rows.clone())
        .grid_template_columns(move || plan.get().columns.clone())
        .state_inline_style(move || styles.get().host)
        .child(decoration)
        .child(body);
    presentation.host_identity(host)
}

fn local_overlay(node: Signal<Arc<Node>>, children: ChildRenderer) -> View {
    let render = children.render;
    let lookup = children.lookup;
    view().child(each(
        children.identities,
        |identity| *identity,
        move |identity, index| {
            let identity = identity.get_untracked();
            let child = lookup(identity);
            view()
                .pointer_events(nsh_core::PointerEvents::BoxNone)
                .style_with(move |s| {
                    if index.get() == 0 {
                        return s;
                    }
                    let parent = node.get();
                    let current = child.map(|child| child.get());
                    let own = current
                        .as_ref()
                        .map_or("", |child| child.string("alignment"));
                    let alignment = if own.is_empty() {
                        parent.string("alignment")
                    } else {
                        own
                    };
                    let s = s.absolute().inset(px(0.0)).flex_col();
                    let s = match alignment {
                        "top-leading" | "top" | "top-trailing" => s.justify_start(),
                        "bottom-leading" | "bottom" | "bottom-trailing" => s.justify_end(),
                        _ => s.justify_center(),
                    };
                    match alignment {
                        "top-leading" | "leading" | "bottom-leading" => s.items_start(),
                        "top-trailing" | "trailing" | "bottom-trailing" => s.items_end(),
                        _ => s.items_center(),
                    }
                })
                .z_index(move || {
                    child.map_or(0, |child| {
                        crate::style::z_index(&child.get())
                            .expect("validated overlay layer")
                            .unwrap_or(0)
                    })
                })
                .child(render(identity))
        },
    ))
}

pub(super) fn element(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    emit: Emit,
    presentation: Presentation,
) -> Option<AnyElement> {
    let theme = presentation.theme;
    let initial = node.get_untracked();
    let id = initial.id;
    Some(match initial.kind.as_str() {
        "icon" => presentation.host(
            ui::icon(
                move || SharedString::from(node.get().string("name").to_owned()),
                move || extent(&node.get(), false),
            )
            .tooltip(tooltip(node, theme)),
        ),
        "spinner" => {
            // The base progress component owns the indeterminate accessibility
            // value; the app supplies a circular indicator instead of a bar.
            let indicator = svg(ImageSrc::svg_markup("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'><path d='M21 12a9 9 0 1 1-9-9'/></svg>"))
                .w_full().h_full().accessibility_elements_hidden(true)
                .style_with(move |s| if theme.get().reduced_motion { s.animate_none() } else { s.animate_spin() });
            presentation.component(
                nsh_base::Progress::element(nsh_base::ProgressProps {
                    indeterminate: true.into(),
                    accessibility_label: Some("Loading".into()).into(),
                    track_class: Some("hidden".into()).into(),
                    ..Default::default()
                })
                .size(move || extent(&node.get(), true))
                .child(indicator),
            )
        }
        "avatar" => presentation.component(
            nsh_base::Avatar::element(nsh_base::AvatarProps {
                name: Prop::bind(move || Some(node.get().string("text").to_owned().into())),
                accessibility_label: Prop::bind(move || Some(label(node))),
                fallback_class: Some("items-center justify-center".into()).into(),
                fallback_style: Prop::bind(move || {
                    ui::part(
                        StyleRefinement::default()
                            .bg(ui::color(theme, "muted"))
                            .text_color(ui::color(theme, "muted-foreground")),
                    )
                }),
                ..Default::default()
            })
            .fill("fallback", text(move || crate::white_space::text(node)))
            .size_10()
            .rounded_full()
            .overflow_hidden(),
        ),
        "status-bar" => presentation.host(
            text(move || crate::white_space::text(node))
                .text_xs()
                .px_3()
                .py_1()
                .rounded(move || ui::radius(theme))
                .bg(move || ui::color(theme, "secondary"))
                .text_color(move || ui::color(theme, "secondary-foreground")),
        ),
        "link" => presentation.component(
            nsh_base::Link::element(nsh_base::LinkProps {
                href: Prop::bind(move || {
                    let node = node.get();
                    (!node.string("url").is_empty()).then(|| node.string("url").to_owned().into())
                }),
                open_with: Prop::bind(move || {
                    if node.get().boolean("press-enabled", false) {
                        nsh_base::LinkOpenWith::App
                    } else {
                        nsh_base::LinkOpenWith::System
                    }
                }),
                disabled: Prop::bind(move || !enabled(node)),
                accessibility_label: Prop::bind(move || {
                    let node = node.get();
                    (!node.string("accessibility-label").is_empty())
                        .then(|| node.string("accessibility-label").to_owned().into())
                }),
                ..Default::default()
            })
            .text_color(move || ui::color(theme, "primary"))
            .focus_visible(|s| {
                s.outline(px(2.0))
                    .outline_color(move || ui::color(theme, "ring"))
            })
            .on_event(move |event: &nsh_base::LinkEvent| {
                if let nsh_base::LinkEvent::PressDetail(detail) = event {
                    let modifiers = i32::from(detail.control)
                        | (i32::from(detail.shift) << 1)
                        | (i32::from(detail.platform) << 2);
                    emit_flag(
                        node,
                        "press-enabled",
                        &emit,
                        Event::NativePress(id, modifiers),
                    );
                }
            })
            .child(link_content(node, children)),
        ),
        "edge-inset" => edge_inset(
            node,
            presentation
                .children
                .clone()
                .expect("retained inset children"),
            presentation,
        ),
        "overlay" => presentation.host(local_overlay(
            node,
            presentation
                .children
                .clone()
                .expect("retained overlay children"),
        )),
        "stack" => presentation.host(layered(
            presentation
                .children
                .clone()
                .expect("retained layer children"),
        )),
        "alert" => {
            let body = presentation
                .children
                .clone()
                .map_or(children, |children| layered(children).into_element());
            presentation.host(
                surface(node, theme)
                    .role(AccessibilityRole::Alert)
                    .label(move || label(node))
                    .child(when(
                        move || !node.get().string("text").is_empty(),
                        move || {
                            text(move || crate::white_space::text(node))
                                .text_sm()
                                .font_weight(nsh_core::element::FontWeight::SEMIBOLD)
                        },
                    ))
                    .child(body),
            )
        }
        "bubble" => {
            let body = presentation
                .children
                .clone()
                .map_or(children, |children| layered(children).into_element());
            presentation.host(
                surface(node, theme)
                    .p_3()
                    .style_with(move |s| {
                        if node.get().string("variant") != "ghost"
                            && !node.get().props.contains_key("width")
                        {
                            s.max_w(relative(0.8))
                        } else {
                            s
                        }
                    })
                    .child(body)
                    .child(when(
                        move || !node.get().string("text").is_empty(),
                        move || {
                            text(move || crate::white_space::text(node))
                                .text_xs()
                                .px_2()
                                .py_1()
                                .rounded_full()
                                .border_1()
                                .border_color(move || ui::color(theme, "border"))
                                .bg(move || ui::color(theme, "background"))
                                .text_color(move || ui::color(theme, "foreground"))
                                .absolute()
                                .bottom(px(0.0))
                                .translate_y(relative(0.5))
                                .style_with(move |s| match node.get().string("text-alignment") {
                                    "end" | "trailing" => s.right(px(12.0)),
                                    "center" => s.left(relative(0.5)).translate_x(relative(-0.5)),
                                    _ => s.left(px(12.0)),
                                })
                        },
                    )),
            )
        }
        _ => return None,
    })
}

fn link_text(node: &Node) -> &str {
    let text = node.string("text");
    if text.is_empty() {
        node.string("url")
    } else {
        text
    }
}

fn link_content(node: Signal<Arc<Node>>, children: AnyElement) -> AnyElement {
    use super::CommandSlot;
    let children = Rc::new(RefCell::new(Some(children)));
    view()
        .flex_row()
        .items_center()
        .gap_1()
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
                            px(16.0),
                        )
                    },
                )
                .into_element(),
                CommandSlot::Label => when(
                    move || !link_text(&node.get()).is_empty(),
                    move || {
                        text(move || {
                            if node.get().string("text").is_empty() {
                                crate::white_space::property(node, "url")
                            } else {
                                crate::white_space::text(node)
                            }
                        })
                    },
                )
                .into_element(),
                CommandSlot::Children => children
                    .borrow_mut()
                    .take()
                    .expect("retained link children"),
            },
        ))
        .into_element()
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use serde_json::{Value, json};
    use std::sync::Mutex;

    struct Fixture {
        kind: &'static str,
        props: Value,
        child: bool,
        events: Arc<Mutex<Vec<Event>>>,
    }

    #[component]
    fn BasicProbe() -> impl IntoElement {
        let fixture = engine_context::<Fixture>().unwrap();
        let node = signal(Arc::new(Node {
            id: 1,
            incarnation: 1,
            kind: fixture.kind.into(),
            props: fixture.props.as_object().unwrap().clone(),
            children: Arc::new(if fixture.child { vec![2] } else { vec![] }),
            ..Default::default()
        }));
        let child = signal(Arc::new(Node {
            id: 2,
            incarnation: 2,
            kind: "text".into(),
            ..Default::default()
        }));
        let identities = signal(if fixture.child { vec![(2, 2)] } else { vec![] });
        let render: Rc<dyn Fn((u64, u64)) -> AnyElement> =
            Rc::new(|_| text("Retained body").test_id("basic-child").into_element());
        let context = ChildRenderer {
            identities,
            press: Rc::new(|_| {}),
            render: render.clone(),
            lookup: Rc::new(move |identity| (identity == (2, 2)).then_some(child)),
        };
        let theme = signal(Arc::new(crate::style::ThemeView::new(
            tokens(),
            dark(),
            reduce_motion(),
        )));
        let presentation = Presentation {
            key: "basic-node".into(),
            test_id: "basic-node".into(),
            style: Rc::new(move || {
                crate::style::compile(
                    &node.get(),
                    &theme.get(),
                    nsh_core::geometry::Size::default(),
                )
                .unwrap()
            }),
            reference: element_ref(),
            theme,
            events: None,
            children: Some(context),
        };
        on_key_with(
            "f8",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let mut next = (*node.get_untracked()).clone();
                next.props.insert("text".into(), json!("Updated"));
                next.props.insert("name".into(), json!("check"));
                next.props.insert("size".into(), json!("lg"));
                next.props.insert("variant".into(), json!("primary"));
                next.props.insert("enabled".into(), json!(false));
                node.set(Arc::new(next));
            },
        );
        let events = fixture.events.clone();
        let children = each(
            identities,
            |identity| *identity,
            move |identity, _| render(identity.get_untracked()),
        );
        view().w_64().child(
            element(
                node,
                children,
                Rc::new(move |event| events.lock().unwrap().push(event)),
                presentation,
            )
            .unwrap(),
        )
    }

    fn start(kind: &'static str, props: Value, child: bool) -> (Headless, Arc<Mutex<Vec<Event>>>) {
        let events = Arc::new(Mutex::new(Vec::new()));
        let mut config = EngineConfig {
            context: EngineContext::default().with(Fixture {
                kind,
                props,
                child,
                events: events.clone(),
            }),
            ..EngineConfig::new(Root::of::<BasicProbe>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        (app, events)
    }

    fn id(app: &Headless, name: &str) -> nsh_core::NodeId {
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some(name))
            .unwrap()
            .id
    }

    #[test]
    fn native_link_uses_keyboard_activation_and_live_disabled_without_remounting() {
        let (mut app, events) = start(
            "link",
            json!({"text":"Portal", "url":"https://example.invalid", "press-enabled":true}),
            false,
        );
        let before = id(&app, "basic-node");
        app.press_key("tab").unwrap();
        app.press_key("enter").unwrap();
        assert_eq!(*events.lock().unwrap(), [Event::NativePress(1, 0)]);
        app.press_key("f8").unwrap();
        app.press_key("enter").unwrap();
        assert_eq!(*events.lock().unwrap(), [Event::NativePress(1, 0)]);
        assert_eq!(id(&app, "basic-node"), before);
    }

    #[test]
    fn internal_hash_link_uses_one_native_owner_and_preserves_pointer_and_keyboard_shift() {
        let (mut app, events) = start(
            "link",
            json!({"text":"Internal page", "url":"#", "press-enabled":true}),
            false,
        );
        let before = id(&app, "basic-node");
        app.hold_keys("ctrl+shift+meta", true).unwrap();
        app.press("text:Internal page").unwrap();
        app.hold_keys("ctrl+shift+meta", false).unwrap();
        assert_eq!(*events.lock().unwrap(), [Event::NativePress(1, 7)]);
        app.press_key("tab").unwrap();
        app.press_key("shift+enter").unwrap();
        assert_eq!(&events.lock().unwrap()[1..], [Event::NativePress(1, 2)]);
        assert!(app.screen().opened_urls().is_empty());
        assert_eq!(id(&app, "basic-node"), before);
    }

    #[test]
    fn url_only_link_shows_destination_and_avatar_keeps_verbatim_fallback() {
        let (mut link, _) = start(
            "link",
            json!({"url":"https://example.invalid", "press-enabled":true}),
            false,
        );
        link.wait_for("text:https://example.invalid").unwrap();
        drop(link);
        let (mut avatar, _) = start("avatar", json!({"text":"XYZ"}), false);
        avatar.wait_for("text:XYZ").unwrap();
        let before = id(&avatar, "basic-node");
        avatar.press_key("f8").unwrap();
        avatar.wait_for("text:Updated").unwrap();
        assert_eq!(id(&avatar, "basic-node"), before);
    }

    #[test]
    fn icon_and_indeterminate_spinner_retain_native_identity_when_size_changes() {
        for (kind, props, initial_extent) in [
            ("icon", json!({"name":"app:unregistered"}), 18.0),
            ("spinner", json!({}), 20.0),
        ] {
            let (mut app, _) = start(kind, props, false);
            let before = app
                .screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some("basic-node"))
                .unwrap();
            assert_eq!(before.bounds.size.width, px(initial_extent));
            if kind == "spinner" {
                assert_eq!(app.screen().count("role:progressbar[Loading]").unwrap(), 1);
            }
            app.press_key("f8").unwrap();
            let after = app
                .screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some("basic-node"))
                .unwrap();
            assert_eq!(before.id, after.id);
            assert_eq!(after.bounds.size.width, px(24.0));
        }
    }

    #[test]
    fn alert_and_bubble_retain_authored_body_when_title_or_reaction_changes() {
        for kind in ["alert", "bubble"] {
            let (mut app, _) = start(kind, json!({"text":"Initial", "width":220}), true);
            app.wait_for("Retained body").unwrap();
            let child = id(&app, "basic-child");
            app.press_key("f8").unwrap();
            app.wait_for("Updated").unwrap();
            assert_eq!(id(&app, "basic-child"), child);
        }
    }

    #[test]
    fn avatar_resource_images_are_rejected_explicitly() {
        let node = Node {
            kind: "avatar".into(),
            props: json!({"text":"XYZ", "image":7})
                .as_object()
                .unwrap()
                .clone(),
            ..Default::default()
        };
        assert!(
            validate(&node)
                .unwrap_err()
                .contains("image-resource bridge")
        );
    }

    #[test]
    fn relative_link_navigation_requires_an_authored_press_handler() {
        for url in ["/settings", "#section"] {
            let mut node = Node {
                kind: "link".into(),
                props: json!({"url":url}).as_object().unwrap().clone(),
                ..Default::default()
            };
            assert!(validate(&node).unwrap_err().contains("external URL"));
            node.props.insert("press-enabled".into(), json!(true));
            validate(&node).unwrap();
        }
    }
    struct LayerFixture(&'static str);

    #[component]
    fn LayerProbe() -> impl IntoElement {
        let kind = engine_context::<LayerFixture>().unwrap().0;
        let node = signal(Arc::new(Node {
            id: 1,
            incarnation: 1,
            kind: kind.into(),
            props: json!({"alignment":"bottom-trailing"})
                .as_object()
                .unwrap()
                .clone(),
            children: Arc::new(vec![2, 3]),
            ..Default::default()
        }));
        let editor = signal(Arc::new(Node {
            id: 2,
            incarnation: 2,
            kind: "text-field".into(),
            ..Default::default()
        }));
        let badge = signal(Arc::new(Node {
            id: 3,
            incarnation: 3,
            kind: "box".into(),
            props: json!({"alignment":"top-leading"})
                .as_object()
                .unwrap()
                .clone(),
            ..Default::default()
        }));
        let identities = signal(vec![(2, 2), (3, 3)]);
        let draft = signal("Draft".to_owned());
        let theme = signal(Arc::new(crate::style::ThemeView::new(
            tokens(),
            dark(),
            reduce_motion(),
        )));
        let render: Rc<dyn Fn((u64, u64)) -> AnyElement> =
            Rc::new(move |identity| match identity.0 {
                2 => ui::input(theme)
                    .w(px(120.0))
                    .h(px(80.0))
                    .test_id("layer-editor")
                    .value(draft)
                    .on_change(move |value: &str| draft.set(value.to_owned()))
                    .into_element(),
                3 => view()
                    .w(px(20.0))
                    .h(px(10.0))
                    .test_id("layer-badge")
                    .into_element(),
                _ => unreachable!(),
            });
        let parts = ChildRenderer {
            identities,
            press: Rc::new(|_| {}),
            render: render.clone(),
            lookup: Rc::new(move |identity| match identity {
                (2, 2) => Some(editor),
                (3, 3) => Some(badge),
                _ => None,
            }),
        };
        let presentation = Presentation {
            key: "layer-root".into(),
            test_id: "layer-root".into(),
            style: Rc::new(move || {
                crate::style::compile(
                    &node.get(),
                    &theme.get(),
                    nsh_core::geometry::Size::default(),
                )
                .unwrap()
            }),
            reference: element_ref(),
            theme,
            events: None,
            children: Some(parts),
        };
        on_key_with(
            "f7",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let mut next = (*badge.get_untracked()).clone();
                next.props.remove("alignment");
                badge.set(Arc::new(next));
            },
        );
        on_key_with(
            "f8",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                batch(|| {
                    identities.set(vec![(3, 3), (2, 2)]);
                    let mut next = (*node.get_untracked()).clone();
                    next.children = Arc::new(vec![3, 2]);
                    node.set(Arc::new(next));
                });
            },
        );
        let children = each(
            identities,
            |identity| *identity,
            move |identity, _| render(identity.get_untracked()),
        );
        view()
            .w_64()
            .h_64()
            .items_start()
            .child(element(node, children, Rc::new(|_| {}), presentation).unwrap())
    }

    fn layer_app(kind: &'static str) -> Headless {
        let mut config = EngineConfig {
            context: EngineContext::default().with(LayerFixture(kind)),
            ..EngineConfig::new(Root::of::<LayerProbe>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        app
    }

    #[test]
    fn local_overlay_preserves_intrinsic_content_and_child_alignment_override() {
        let mut app = layer_app("overlay");
        let find = |app: &Headless, name: &str| {
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some(name))
                .unwrap()
        };
        let root = find(&app, "layer-root");
        let badge = find(&app, "layer-badge");
        assert_eq!(root.bounds.size.width, px(120.0));
        assert_eq!(root.bounds.size.height, px(80.0));
        assert_eq!(badge.bounds.origin, root.bounds.origin);
        app.press_key("f7").unwrap();
        let moved = find(&app, "layer-badge");
        assert_eq!(moved.id, badge.id);
        assert_eq!(moved.bounds.origin.x, root.bounds.origin.x + px(100.0));
        assert_eq!(moved.bounds.origin.y, root.bounds.origin.y + px(70.0));
    }

    #[test]
    fn layered_editor_keeps_native_identity_draft_and_keyboard_focus_across_reorder() {
        for kind in ["stack", "overlay"] {
            let mut app = layer_app(kind);
            let editor = id(&app, "layer-editor");
            app.type_text("id:layer-editor", "Edited").unwrap();
            let draft = app
                .screen()
                .input_text("id:layer-editor")
                .unwrap()
                .unwrap()
                .to_owned();
            app.press_key("f8").unwrap();
            assert_eq!(id(&app, "layer-editor"), editor);
            app.press_key("x").unwrap();
            assert_eq!(
                app.screen().input_text("id:layer-editor").unwrap(),
                Some(format!("{draft}x").as_str())
            );
        }
    }

    struct InsetFixture {
        edge: &'static str,
    }

    #[component]
    fn InsetProbe() -> impl IntoElement {
        let fixture = engine_context::<InsetFixture>().unwrap();
        let node=signal(Arc::new(Node { id:1,incarnation:1,kind:"edge-inset".into(),
            props:json!({"edge":fixture.edge,"width":200,"height":160,"gap":5,"padding":4,"padding-horizontal":6,"padding-top":8,"padding-right":12,"border-width":2,"background":"secondary","foreground":"destructive"}).as_object().unwrap().clone(),
            children:Arc::new(vec![2,3,4]),..Default::default() }));
        let identities = signal(vec![(2, 2), (3, 3), (4, 4)]);
        let theme = signal(Arc::new(crate::style::ThemeView::new(
            tokens(),
            dark(),
            reduce_motion(),
        )));
        let draft = signal("Draft".to_owned());
        let render: Rc<dyn Fn((u64, u64)) -> AnyElement> =
            Rc::new(move |identity| match identity.0 {
                2 => view()
                    .w_full()
                    .h_full()
                    .test_id("inset-main")
                    .child(text("Main"))
                    .into_element(),
                3 => ui::input(theme)
                    .min_h(px(0.0))
                    .p_0()
                    .w(px(40.0))
                    .h(px(20.0))
                    .test_id("inset-editor")
                    .value(draft)
                    .on_change(move |value: &str| draft.set(value.to_owned()))
                    .into_element(),
                4 => view()
                    .w(px(30.0))
                    .h(px(15.0))
                    .test_id("inset-pin")
                    .child(text("Pin"))
                    .into_element(),
                _ => unreachable!(),
            });
        let children = ChildRenderer {
            identities,
            press: Rc::new(|_| {}),
            render: render.clone(),
            lookup: Rc::new(|_| None),
        };
        let presentation = Presentation {
            key: "inset-root".into(),
            test_id: "inset-root".into(),
            reference: element_ref(),
            theme,
            events: None,
            children: Some(children),
            style: Rc::new(move || {
                crate::style::compile(
                    &node.get(),
                    &theme.get(),
                    nsh_core::geometry::Size::default(),
                )
                .unwrap()
            }),
        };
        for (key, visible) in [("f6", false), ("f5", true)] {
            on_key_with(
                key,
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| {
                    let mut next = (*node.get_untracked()).clone();
                    next.props.insert("visible".into(), json!(visible));
                    node.set(Arc::new(next));
                },
            );
        }
        on_key_with(
            "f4",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                batch(|| {
                    identities.set(vec![(3, 3), (2, 2), (4, 4)]);
                    let mut next = (*node.get_untracked()).clone();
                    next.children = Arc::new(vec![3, 2, 4]);
                    node.set(Arc::new(next));
                });
            },
        );
        let body = each(
            identities,
            |identity| *identity,
            move |identity, _| render(identity.get_untracked()),
        );
        view()
            .items_start()
            .child(element(node, body, Rc::new(|_| {}), presentation).unwrap())
    }

    fn inset_app(edge: &'static str, rtl: bool) -> Headless {
        let mut config = EngineConfig {
            context: EngineContext::default().with(InsetFixture { edge }),
            ..EngineConfig::new(Root::of::<InsetProbe>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        config.environment.rtl = rtl;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        app
    }

    #[test]
    fn edge_inset_measures_all_pinned_children_and_scopes_surface_spacing_to_pins() {
        let find = |app: &Headless, name: &str| {
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some(name))
                .unwrap()
        };
        for edge in ["top", "bottom", "leading", "trailing"] {
            let mut app = inset_app(edge, false);
            let root = find(&app, "inset-root");
            let main = find(&app, "inset-main");
            let first = find(&app, "inset-editor");
            let second = find(&app, "inset-pin");
            let paint = find(&app, "lui-inset-decoration-1");
            assert_eq!(root.bounds.size.width, px(200.0));
            assert_eq!(root.bounds.size.height, px(160.0));
            if matches!(edge, "top" | "bottom") {
                assert_eq!(main.bounds.size.height, px(104.0));
                assert_eq!(main.bounds.size.width, px(200.0));
                assert_eq!(paint.bounds.size.height, px(51.0));
                assert_eq!(first.bounds.origin.x - root.bounds.origin.x, px(8.0));
                assert_eq!(second.bounds.origin.y - first.bounds.origin.y, px(20.0));
                let expected = if edge == "top" { 56.0 } else { 0.0 };
                assert_eq!(main.bounds.origin.y - root.bounds.origin.y, px(expected));
            } else {
                assert_eq!(main.bounds.size.width, px(103.0));
                assert_eq!(main.bounds.size.height, px(160.0));
                assert_eq!(paint.bounds.size.width, px(92.0));
                assert_eq!(first.bounds.origin.y - root.bounds.origin.y, px(10.0));
                assert_eq!(second.bounds.origin.x - first.bounds.origin.x, px(40.0));
                let expected = if edge == "leading" { 97.0 } else { 0.0 };
                assert_eq!(main.bounds.origin.x - root.bounds.origin.x, px(expected));
            }
            assert_ne!(
                app.screen().span_style("text:Main").unwrap().color,
                app.screen().span_style("text:Pin").unwrap().color
            );
            let first_id = first.id;
            let second_id = second.id;
            app.press_key("f6").unwrap();
            let expanded = find(&app, "inset-main");
            assert_eq!(expanded.bounds.size, root.bounds.size);
            app.press_key("f5").unwrap();
            assert_eq!(find(&app, "inset-editor").id, first_id);
            assert_eq!(find(&app, "inset-pin").id, second_id);
        }
    }

    #[test]
    fn edge_inset_preserves_editor_identity_draft_and_focus_when_main_role_changes() {
        let mut app = inset_app("top", false);
        let editor = id(&app, "inset-editor");
        app.type_text("id:inset-editor", "Edited").unwrap();
        let before = app
            .screen()
            .input_text("id:inset-editor")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("f4").unwrap();
        app.press_key("x").unwrap();
        assert_eq!(id(&app, "inset-editor"), editor);
        assert_eq!(
            app.screen().input_text("id:inset-editor").unwrap(),
            Some(format!("{before}x").as_str())
        );
        app.press_key("f6").unwrap();
        app.press_key("y").unwrap();
        assert_eq!(
            app.screen().input_text("id:inset-editor").unwrap(),
            Some(format!("{before}xy").as_str())
        );
    }

    #[test]
    fn edge_inset_logical_edges_keep_physical_padding_in_rtl() {
        let find = |app: &Headless, name: &str| {
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some(name))
                .unwrap()
        };
        for edge in ["leading", "trailing"] {
            let app = inset_app(edge, true);
            let root = find(&app, "inset-root");
            let main = find(&app, "inset-main");
            let first = find(&app, "inset-editor");
            let second = find(&app, "inset-pin");
            assert_eq!(main.bounds.size.width, px(103.0));
            assert_eq!(first.bounds.origin.x - second.bounds.origin.x, px(30.0));
            let expected = if edge == "leading" { 146.0 } else { 38.0 };
            assert_eq!(first.bounds.origin.x - root.bounds.origin.x, px(expected));
            let expected = if edge == "leading" { 0.0 } else { 97.0 };
            assert_eq!(main.bounds.origin.x - root.bounds.origin.x, px(expected));
        }
    }

    #[component]
    fn InsetRejectionProbe() -> impl IntoElement {
        use crate::{render::Renderer, wire::Batch};
        let renderer = Renderer::new(|_, _| {});
        let patch = |generation, ops| {
            Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
        };
        renderer
            .apply(patch(
                1,
                json!([
                    {"op":"create-node","id":1,"kind":"edge-inset"},
                    {"op":"set-prop","id":1,"property":"edge","value":"top"},
                    {"op":"set-prop","id":1,"property":"width","value":200},
                    {"op":"set-prop","id":1,"property":"height","value":80},
                    {"op":"create-node","id":2,"kind":"text"},
                    {"op":"set-prop","id":2,"property":"text","value":"Before inset rejection"},
                    {"op":"insert-child","parent":1,"child":2,"index":0}
                ]),
            ))
            .unwrap();
        renderer.set_root(1).unwrap();
        for (property, value) in [
            ("hover-background", json!("primary")),
            ("opacity", json!(0.5)),
            ("shadow", json!("sm")),
        ] {
            assert!(renderer.apply(patch(2,json!([
                {"op":"set-prop","id":2,"property":"text","value":"Must not publish inset edit"},
                {"op":"set-prop","id":1,"property":property,"value":value}
            ]))).unwrap_err().contains("edge-inset pooled"));
        }
        renderer.apply(patch(2,json!([{"op":"set-prop","id":2,"property":"text","value":"Recovered inset generation"}]))).unwrap();
        renderer.element()
    }

    #[test]
    fn edge_inset_rejects_unavailable_pooled_paint_atomically() {
        let mut app =
            Headless::start(EngineConfig::new(Root::of::<InsetRejectionProbe>())).unwrap();
        app.wait_for("Recovered inset generation").unwrap();
        assert_eq!(
            app.screen()
                .count("text:Must not publish inset edit")
                .unwrap(),
            0
        );
    }

    struct InsetAppearFixture(Arc<Mutex<Vec<Event>>>);
    #[component]
    fn InsetAppearProbe() -> impl IntoElement {
        use crate::{render::Renderer, wire::Batch};
        let events = engine_context::<InsetAppearFixture>().unwrap().0.clone();
        let renderer = Renderer::new(move |event, _| events.lock().unwrap().push(event));
        let patch = |generation, ops| {
            Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
        };
        renderer
            .apply(patch(
                1,
                json!([
                    {"op":"create-node","id":1,"kind":"edge-inset"},
                    {"op":"set-prop","id":1,"property":"edge","value":"top"},
                    {"op":"set-prop","id":1,"property":"visible","value":false},
                    {"op":"set-prop","id":1,"property":"width","value":200},
                    {"op":"set-prop","id":1,"property":"height","value":100},
                    {"op":"create-node","id":2,"kind":"text"},
                    {"op":"set-prop","id":2,"property":"text","value":"Main appear"},
                    {"op":"set-prop","id":2,"property":"appear-enabled","value":true},
                    {"op":"create-node","id":3,"kind":"column"},
                    {"op":"set-prop","id":3,"property":"appear-enabled","value":true},
                    {"op":"create-node","id":4,"kind":"text"},
                    {"op":"set-prop","id":4,"property":"text","value":"Pinned appear"},
                    {"op":"set-prop","id":4,"property":"appear-enabled","value":true},
                    {"op":"insert-child","parent":3,"child":4,"index":0},
                    {"op":"insert-child","parent":1,"child":2,"index":0},
                    {"op":"insert-child","parent":1,"child":3,"index":1}
                ]),
            ))
            .unwrap();
        renderer.set_root(1).unwrap();
        let generation = Rc::new(std::cell::Cell::new(1));
        for (key, visible) in [("f5", true), ("f6", false)] {
            let renderer = renderer.clone();
            let generation = generation.clone();
            on_key_with(
                key,
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| {
                    let next = generation.get() + 1;
                    renderer
                        .apply(patch(
                            next,
                            json!([{"op":"set-prop","id":1,"property":"visible","value":visible}]),
                        ))
                        .unwrap();
                    generation.set(next);
                },
            );
        }
        let repaint = renderer.clone();
        on_key_with(
            "f7",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let next = generation.get() + 1;
                repaint
                    .apply(patch(
                        next,
                        json!([{"op":"set-prop","id":1,"property":"background","value":"primary"}]),
                    ))
                    .unwrap();
                generation.set(next);
            },
        );
        renderer.element()
    }

    #[test]
    fn edge_inset_appear_follows_visibility_without_replacing_native_nodes() {
        let events = Arc::new(Mutex::new(Vec::new()));
        let config = EngineConfig {
            context: EngineContext::default().with(InsetAppearFixture(events.clone())),
            ..EngineConfig::new(Root::of::<InsetAppearProbe>())
        };
        let mut app = Headless::start(config).unwrap();
        app.wait_for("text:Main appear").unwrap();
        app.press_key("f6").unwrap();
        let count = |target| {
            events
                .lock()
                .unwrap()
                .iter()
                .filter(|event| matches!(event, Event::Appear(id) if *id==target))
                .count()
        };
        assert_eq!(count(3), 0, "an initially hidden pinned node appeared");
        assert_eq!(
            count(4),
            0,
            "an initially hidden pinned descendant appeared"
        );
        app.press_key("f5").unwrap();
        app.wait_for("text:Pinned appear").unwrap();
        assert_eq!(count(3), 1);
        assert_eq!(count(4), 1);
        app.press_key("f7").unwrap();
        assert_eq!(count(3), 1);
        assert_eq!(count(4), 1);
        let pinned = id(&app, "lui-3");
        app.press_key("f6").unwrap();
        app.press_key("f5").unwrap();
        app.wait_for("text:Pinned appear").unwrap();
        assert_eq!(count(3), 2);
        assert_eq!(count(4), 2);
        assert_eq!(id(&app, "lui-3"), pinned);
    }
}

#[cfg(test)]
#[path = "basic/stack_layout_tests.rs"]
mod stack_layout_tests;
