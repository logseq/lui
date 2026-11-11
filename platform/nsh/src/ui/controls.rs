//! Themed parts for controls whose behavior is supplied by NSH.
use super::{Theme, color, part, radius};
use nsh_core::{
    element::{ComponentElement, StyleRefinement},
    prelude::*,
};

const HOVER_MS: f32 = 120.0;
const FAST_MS: f32 = 180.0;

fn hover_duration() -> f32 {
    if reduce_motion() { 0.0 } else { HOVER_MS }
}
fn fast_duration() -> f32 {
    if reduce_motion() { 0.0 } else { FAST_MS }
}

pub(super) fn choice<C: Component>(
    element: ComponentElement<C>,
    theme: Theme,
) -> ComponentElement<C> {
    element
        .min_h_8()
        .flex_row()
        .items_center()
        .gap_2()
        .text_sm()
        .text_color(move || color(theme, "foreground"))
        .transition_colors()
        .duration(hover_duration)
        .hover(|s| s.bg(move || color(theme, "accent")))
        .active(|s| s.bg(move || color(theme, "muted")))
        .focus_visible(|s| {
            s.outline(px(2.0))
                .outline_color(move || color(theme, "ring"))
        })
        .disabled_style(|s| s.opacity(0.5))
}

pub fn switch(props: nsh_base::SwitchProps, theme: Theme) -> ComponentElement<nsh_base::Switch> {
    choice(nsh_base::Switch::element(nsh_base::SwitchProps {
        track_class: Some("w-9 p-0.5 rounded-full bg-muted transition-colors duration-180 checked:bg-primary motion-reduce:duration-0".into()).into(),
        thumb_class: Some("size-4 rounded-full bg-background shadow-sm transition-transform duration-180 checked:translate-x-4 motion-reduce:duration-0".into()).into(),
        track_style: Prop::bind(move || part(StyleRefinement::default().bg(color(theme,"muted")).checked(|s| s.bg(color(theme,"primary"))))),
        thumb_style: Prop::bind(move || part(StyleRefinement::default().bg(color(theme,"background")))),
        ..props
    }), theme)
}

pub fn radio(props: nsh_base::RadioProps, theme: Theme) -> ComponentElement<nsh_base::Radio> {
    let checked = props.checked;
    choice(nsh_base::Radio::element(props), theme).child(
        view()
            .size_4()
            .rounded_full()
            .border_1()
            .border_color(move || {
                if checked.get() {
                    color(theme, "primary")
                } else {
                    color(theme, "border")
                }
            })
            .items_center()
            .justify_center()
            .accessibility_elements_hidden(true)
            .child(
                view()
                    .size_2()
                    .rounded_full()
                    .bg(move || color(theme, "primary"))
                    .opacity(move || if checked.get() { 1.0_f32 } else { 0.0_f32 }),
            ),
    )
}

pub fn toggle(props: nsh_base::ToggleProps, theme: Theme) -> ComponentElement<nsh_base::Toggle> {
    choice(nsh_base::Toggle::element(props), theme)
        .px_3()
        .py_1()
        .rounded(move || radius(theme))
        .bg(move || color(theme, "secondary"))
        .aria_pressed(|s| {
            s.bg(move || color(theme, "primary"))
                .text_color(move || color(theme, "primary-foreground"))
        })
}

pub fn slider(props: nsh_base::SliderProps, theme: Theme) -> ComponentElement<nsh_base::Slider> {
    nsh_base::Slider::element(nsh_base::SliderProps {
        track_class: Some("h-8 justify-center".into()).into(),
        indicator_class: Some("h-1.5 rounded-full bg-muted".into()).into(),
        range_class: Some("rounded-full bg-primary".into()).into(),
        thumb_class: Some("size-4 rounded-full bg-background border border-primary focus-visible:outline-2 focus-visible:outline-ring disabled:opacity-50".into()).into(),
        indicator_style: Prop::bind(move || part(StyleRefinement::default().bg(color(theme,"muted")))),
        range_style: Prop::bind(move || part(StyleRefinement::default().bg(color(theme,"primary")))),
        thumb_style: Prop::bind(move || {
            let mut thumb = view().bg(color(theme,"background")).border_color(color(theme,"primary"))
                .focus_visible(|s|s.outline_color(color(theme,"ring")));
            part(thumb.style().clone())
        }),
        ..props
    }).min_w_24().disabled_style(|s| s.opacity(0.5))
}

pub fn progress(
    props: nsh_base::ProgressProps,
    theme: Theme,
) -> ComponentElement<nsh_base::Progress> {
    nsh_base::Progress::element(nsh_base::ProgressProps {
        track_class: Some("h-2 rounded-full bg-muted overflow-hidden".into()).into(),
        indicator_class: Some("h-2 rounded-full bg-primary".into()).into(),
        track_style: Prop::bind(move || part(StyleRefinement::default().bg(color(theme, "muted")))),
        indicator_style: Prop::bind(move || {
            part(StyleRefinement::default().bg(color(theme, "primary")))
        }),
        ..props
    })
    .min_w_24()
}

pub fn number_input(
    props: nsh_base::NumberInputProps,
    theme: Theme,
) -> ComponentElement<nsh_base::NumberInput> {
    nsh_base::NumberInput::element(nsh_base::NumberInputProps {
        input_class: Some("min-h-8 min-w-12 px-2 py-1 text-sm text-center bg-background text-foreground border border-input rounded-(--radius) focus:border-ring".into()).into(),
        decrement_button_class: Some("min-h-8 min-w-8 items-center justify-center rounded-(--radius) bg-secondary hover:bg-accent active:bg-muted disabled:opacity-50".into()).into(),
        increment_button_class: Some("min-h-8 min-w-8 items-center justify-center rounded-(--radius) bg-secondary hover:bg-accent active:bg-muted disabled:opacity-50".into()).into(),
        input_style: Prop::bind(move || {
            let mut input = view().bg(color(theme,"background")).text_color(color(theme,"foreground"))
                .border_color(color(theme,"input")).rounded(radius(theme)).focus(|s|s.border_color(color(theme,"ring")));
            input.style().clone().into()
        }),
        decrement_button_style: Prop::bind(move || { let mut v=view().bg(color(theme,"secondary")).rounded(radius(theme)).hover(|s|s.bg(color(theme,"accent"))).active(|s|s.bg(color(theme,"muted"))); part(v.style().clone()) }),
        increment_button_style: Prop::bind(move || { let mut v=view().bg(color(theme,"secondary")).rounded(radius(theme)).hover(|s|s.bg(color(theme,"accent"))).active(|s|s.bg(color(theme,"muted"))); part(v.style().clone()) }),
        ..props
    }).flex_row().items_center().gap_1()
        .fill("decrementButton", text("−").text_color(move || color(theme, "foreground")))
        .fill("incrementButton", text("+").text_color(move || color(theme, "foreground")))
}

#[derive(Clone)]
struct TabsContext;

#[derive(Clone, PartialEq, Default)]
pub struct TabsProps {
    pub theme: Prop<Option<Theme>>,
    pub vertical: Prop<bool>,
    pub label: Prop<SharedString>,
    pub gap: Prop<Points>,
    pub children: Prop<Children>,
}

pub struct Tabs;
impl Component for Tabs {
    type Props = TabsProps;
    type Event = NoEvent;
    fn view(props: TabsProps, _: Scope<NoEvent>) -> impl IntoElement {
        tabs(props)
    }
}
fn tabs(props: TabsProps) -> impl IntoElement {
    let theme = props.theme.get_untracked().expect("scoped tabs theme");
    provide_context(TabsContext);
    // The named group is semantic context, not an identity wrapper: NSH
    // Tabs owns its tab-list role, native roving focus and following indicator.
    view()
        .role(AccessibilityRole::Group)
        .label(move || props.label.get())
        .child(
            nsh_base::Tabs::element(nsh_base::TabsProps {
                indicator_class: Some("absolute bottom-0 h-0.5 rounded-full".into()).into(),
                indicator_style: Prop::bind(move || {
                    part(StyleRefinement::default().bg(color(theme, "primary")))
                }),
                ..Default::default()
            })
            .gap(move || Length::from(props.gap.get()))
            .style_with(move |s| {
                if props.vertical.get() {
                    s.flex_col()
                } else {
                    s.flex_row()
                }
            })
            .child(props.children),
        )
}

pub fn in_tabs() -> bool {
    use_context::<TabsContext>().is_some()
}

pub fn tab(props: nsh_base::TabProps, theme: Theme) -> ComponentElement<nsh_base::Tab> {
    choice(nsh_base::Tab::element(props), theme)
        .px_3()
        .py_1()
        .selected(|s| s.text_color(move || color(theme, "primary")))
}

pub fn menu_item(
    props: nsh_base::MenuItemProps,
    theme: Theme,
) -> ComponentElement<nsh_base::MenuItem> {
    choice(nsh_base::MenuItem::element(props), theme)
        .px_3()
        .py_1()
        .rounded(move || radius(theme))
}

pub fn panel(theme: Theme) -> View {
    view()
        .p_4()
        .gap_3()
        .rounded(move || radius(theme))
        .bg(move || color(theme, "popover"))
        .text_color(move || color(theme, "popover-foreground"))
        .border_1()
        .border_color(move || color(theme, "border"))
        .shadow_lg()
}

pub fn button_motion(
    props: nsh_base::ButtonProps,
    theme: Theme,
) -> ComponentElement<nsh_base::Button> {
    super::button(props, theme)
        .transition_colors()
        .duration(fast_duration)
}

/// The shared command's value, label and children remain owned by LUI.
#[derive(Clone, PartialEq, Default)]
pub struct CommandButtonProps {
    pub theme: Prop<Option<Theme>>,
    pub selected: Prop<bool>,
    pub disabled: Prop<bool>,
    pub label: Prop<SharedString>,
    pub variant: Prop<SharedString>,
    pub size: Prop<SharedString>,
    pub children: Prop<Children>,
}

#[derive(Clone, PartialEq, Event)]
pub enum CommandButtonEvent {
    Press,
}

/// Select the native button or tab behavior when the parent context exists.
pub struct CommandButton;
impl Component for CommandButton {
    type Props = CommandButtonProps;
    type Event = CommandButtonEvent;
    fn view(props: CommandButtonProps, cx: Scope<CommandButtonEvent>) -> impl IntoElement {
        command_button(props, cx)
    }
}
fn command_button(props: CommandButtonProps, cx: Scope<CommandButtonEvent>) -> impl IntoElement {
    let theme = props.theme.get_untracked().expect("scoped command theme");
    if in_tabs() {
        tab(
            nsh_base::TabProps {
                selected: props.selected,
                disabled: props.disabled,
                accessibility_label: Prop::bind(move || Some(props.label.get())),
                ..Default::default()
            },
            theme,
        )
        .on_event(move |_: &nsh_base::TabEvent| cx.emit(CommandButtonEvent::Press))
        .child(props.children)
        .into_element()
    } else {
        command_appearance(
            button_motion(
                nsh_base::ButtonProps {
                    selected: props.selected,
                    disabled: props.disabled,
                    accessibility_label: Prop::bind(move || Some(props.label.get())),
                    ..Default::default()
                },
                theme,
            ),
            theme,
            props.variant,
            props.size,
        )
        .on_event(move |event: &nsh_base::ButtonEvent| {
            if matches!(event, nsh_base::ButtonEvent::Press) {
                cx.emit(CommandButtonEvent::Press);
            }
        })
        .child(props.children)
        .into_element()
    }
}

/// One authored size controls geometry and typography; explicit LUI styles
/// are applied by the retained renderer after these shared defaults.
pub(crate) fn command_appearance<C: Component>(
    element: ComponentElement<C>,
    theme: Theme,
    variant: Prop<SharedString>,
    size: Prop<SharedString>,
) -> ComponentElement<C> {
    element
        .flex_row()
        .items_center()
        .justify_center()
        .gap_2()
        .style_with(move |_| {
            let s = view();
            let s = match size.get().as_ref() {
                "sm" => s.min_h_6().px_2().py_1().text_xs(),
                "lg" => s.min_h_10().px_4().py_2().text_base(),
                "icon" => s.w_8().h_8().p_0().text_sm(),
                _ => s.min_h_8().px_3().py_1().text_sm(),
            };
            let variant = variant.get();
            let (background, foreground) = match variant.as_ref() {
                "primary" => ("primary", "primary-foreground"),
                "destructive" => ("destructive", "primary-foreground"),
                "ghost" | "outline" => ("background", "foreground"),
                _ => ("secondary", "secondary-foreground"),
            };
            let s = s
                .bg(if variant == "ghost" || variant == "outline" {
                    color(theme, background).opacity(0.0)
                } else {
                    color(theme, background)
                })
                .text_color(color(theme, foreground))
                .border(px(0.0));
            let s = if variant == "outline" {
                s.border_1().border_color(color(theme, "border"))
            } else {
                s
            };
            let mut styled = s
                .hover(|s| {
                    if variant == "primary" || variant == "destructive" {
                        s.bg(color(theme, background).opacity(0.9))
                    } else {
                        s.bg(color(theme, "accent"))
                            .text_color(color(theme, "accent-foreground"))
                    }
                })
                .selected(|s| {
                    s.bg(color(theme, "primary"))
                        .text_color(color(theme, "primary-foreground"))
                })
                .aria_pressed(|s| {
                    s.bg(color(theme, "primary"))
                        .text_color(color(theme, "primary-foreground"))
                });
            styled.style().clone()
        })
}

// These private Rust components carry a retained theme signal. They are not JS
// exports; the public Component/Props traits keep that signal typed in Rust.
macro_rules! rust_props {
    ($name:ty) => {
        impl Props for $name {
            fn spec(_: &mut nsh_core::element::TsTypes) -> Vec<nsh_core::element::PropSpec> {
                Vec::new()
            }
            fn initial() -> Self {
                Self::default()
            }
            fn set(
                &mut self,
                name: &str,
                _: Option<nsh_core::element::AnyValue>,
            ) -> Result<bool, nsh_core::element::PropError> {
                Err(nsh_core::element::PropError(format!(
                    "private Rust UI prop {name}"
                )))
            }
            fn set_slot(&mut self, _: &str, _: Option<Slot>) -> bool {
                false
            }
            fn set_children(&mut self, children: Children) -> bool {
                self.children = children.into();
                true
            }
        }
    };
}
rust_props!(TabsProps);
rust_props!(CommandButtonProps);
