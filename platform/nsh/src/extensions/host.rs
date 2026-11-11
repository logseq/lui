//! Public NSH component root projection, without an extra native layout wrapper.
use super::{Implementation, Schema};
use crate::store::Node;
use nsh_core::{
    element::{AnyValue, PropError, PropSpec, TsTypes},
    prelude::*,
};
use serde_json::{Map, Value};
use std::{rc::Rc, sync::Arc};

pub type Identity = (u64, u64);
pub type ChildLookup = Rc<dyn Fn(Identity) -> Option<Signal<Arc<Node>>>>;

/// Retained capabilities over the existing renderer entries, never a second tree.
#[derive(Clone)]
pub struct ExtensionChildren {
    pub identities: Signal<Vec<Identity>>,
    pub render: Rc<dyn Fn(Identity) -> AnyElement>,
    pub lookup: ChildLookup,
}
impl ExtensionChildren {
    pub fn element(&self) -> AnyElement {
        let render = self.render.clone();
        each(
            self.identities,
            |identity| *identity,
            move |identity, _| render(identity.get_untracked()),
        )
        .into_element()
    }
}

type Emit = Rc<dyn Fn(&str, Map<String, Value>) -> Result<bool, String>>;
/// Declared scalar events only. Disposed/replaced node callbacks cannot emit.
#[derive(Clone)]
pub struct ExtensionEmitter(pub(crate) Emit);
impl ExtensionEmitter {
    pub fn emit(&self, name: &str, values: Map<String, Value>) -> Result<(), String> {
        if self.try_emit(name, values)? {
            Ok(())
        } else {
            Err("extension node was disposed or replaced".into())
        }
    }
    /// `Ok(false)` is a retired incarnation; malformed payloads remain errors.
    pub fn try_emit(&self, name: &str, values: Map<String, Value>) -> Result<bool, String> {
        (self.0)(name, values)
    }
}

/// Created once for a retained extension incarnation. Read `node`/`property` in bindings.
#[derive(Clone)]
pub struct ExtensionContext {
    pub node: Signal<Arc<Node>>,
    pub children: ExtensionChildren,
    pub reference: ElementRef,
    pub emitter: ExtensionEmitter,
    pub(crate) schema: Arc<Schema>,
    pub(crate) theme: Signal<Arc<crate::style::ThemeView>>,
}
impl ExtensionContext {
    /// Resolve paint using this entry's existing scoped theme signal.
    pub fn color(&self, expression: &str) -> Result<nsh_core::element::AdaptiveColor, String> {
        self.theme.get().color(expression)
    }
    /// Resolve authored variable expressions without rebuilding a CSS cascade.
    pub fn resolve_text(&self, expression: &str) -> Result<String, String> {
        self.theme.get().text(expression)
    }

    /// Omitted properties resolve their canonical schema default without mutating wire state.
    pub fn property(&self, name: &str) -> Option<Value> {
        let node = self.node.get();
        node.extension
            .as_ref()?
            .properties
            .get(name)
            .cloned()
            .or_else(|| {
                self.schema
                    .properties
                    .iter()
                    .find(|p| p.name == name)?
                    .default
                    .clone()
            })
    }
}

/// Typed public component root. Styling it projects onto the actual retained child root.
pub type TweakTarget = ComponentElement<RetainedContent>;
#[doc(hidden)]
pub struct RetainedContent;
#[doc(hidden)]
#[derive(Clone, Default)]
pub struct ContentProps(Option<Rc<dyn Fn() -> AnyElement>>);
impl PartialEq for ContentProps {
    fn eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (Some(a), Some(b)) => Rc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        }
    }
}
impl Props for ContentProps {
    fn spec(_: &mut TsTypes) -> Vec<PropSpec> {
        Vec::new()
    }
    fn initial() -> Self {
        Self::default()
    }
    fn set(&mut self, name: &str, _: Option<AnyValue>) -> Result<bool, PropError> {
        Err(PropError(format!(
            "internal extension host has no prop {name}"
        )))
    }
    fn set_slot(&mut self, _: &str, _: Option<Slot>) -> bool {
        false
    }
    fn set_children(&mut self, _: Children) -> bool {
        false
    }
}
impl Component for RetainedContent {
    type Props = ContentProps;
    type Event = NoEvent;
    fn view(props: Self::Props, _: Scope<Self::Event>) -> impl IntoElement {
        props
            .0
            .expect("internal extension host requires a trusted factory")()
    }
}

pub(crate) fn mount(
    context: ExtensionContext,
    implementation: Implementation,
    reference: ElementRef,
) -> AnyElement {
    let identity = context.node.get_untracked();
    let key = format!("lui-extension-{}-{}", identity.id, identity.incarnation);
    RetainedContent::element(ContentProps(Some(Rc::new(move || match &implementation {
        Implementation::Component(factory) => factory(context.clone()),
        Implementation::Tweak(modifier) => {
            let children = context.children.clone();
            let target = RetainedContent::element(ContentProps(Some(Rc::new(move || {
                let identity = children.identities.get_untracked()[0];
                (children.render)(identity)
            }))));
            modifier(context.clone(), target)
        }
    }))))
    .element_ref(&reference)
    .key(key)
    .into_element()
}
