//! Opt-in native-sheet automation on the existing canonical agent owner and queue.
use crate::{app::ApplicationMutations, render::Renderer};
use serde::Deserialize;
use serde_json::{Value, json};

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
type NativeState = std::sync::Arc<dispatch2::MainThreadBound<std::cell::RefCell<macos::State>>>;

#[derive(Deserialize)]
#[serde(tag = "op", deny_unknown_fields)]
enum Request {
    #[serde(rename = "native-dialog")]
    Inspect { selector: String },
    #[serde(rename = "native-dialog-answer")]
    Answer { token: String, button: String },
}

fn bounded(value: &str, limit: usize) -> bool {
    !value.is_empty() && value.len() <= limit && !value.chars().any(char::is_control)
}

pub(super) fn find(request: &Value) -> Result<String, String> {
    match serde_json::from_value(request.clone()).map_err(|error| error.to_string())? {
        Request::Inspect { selector } if bounded(&selector, 1024) => {
            Ok(json!({"op":"find","selector":selector}).to_string())
        }
        _ => Err("native-dialog requires one bounded nonempty owner selector".into()),
    }
}

fn answer_request(request: &str) -> Result<(String, String), String> {
    match serde_json::from_str(request).map_err(|error| error.to_string())? {
        Request::Answer { token, button } if bounded(&token, 64) && bounded(&button, 1024) => {
            Ok((token, button))
        }
        _ => Err("native-dialog-answer requires a current token and exact button label".into()),
    }
}

#[derive(Clone)]
struct Owner {
    node: u64,
    incarnation: u64,
    identifier: String,
}
impl Owner {
    fn capture(renderer: &Renderer, node: u64) -> Result<Self, String> {
        let incarnation = renderer
            .current_incarnation(node)
            .ok_or("native-dialog owner is retired")?;
        let identifier = renderer.native_presentation_identifier(node, incarnation)?;
        if !bounded(&identifier, 1024) {
            return Err("native-dialog requires a bounded mounted owner identifier".into());
        }
        Ok(Self {
            node,
            incarnation,
            identifier,
        })
    }
    fn check(
        &self,
        renderer: &Renderer,
        admission: Option<&ApplicationMutations>,
    ) -> Result<(), String> {
        if let Some(error) = renderer.failure() {
            return Err(error);
        }
        if let Some(admission) = admission {
            admission.check()?;
        }
        if renderer.current_incarnation(self.node) != Some(self.incarnation) {
            return Err("native-dialog owner incarnation changed".into());
        }
        if renderer.native_presentation_identifier(self.node, self.incarnation)? != self.identifier
        {
            return Err("native-dialog native owner changed".into());
        }
        // An owner anchor locates a window, not an action. A busy Settings button
        // can be disabled while its sheet is open; only the sheet button is activated.
        Ok(())
    }
}

#[derive(Default)]
pub(crate) struct Dialogs {
    owner: Option<Owner>,
    #[cfg(target_os = "macos")]
    state: Option<NativeState>,
}

#[cfg(target_os = "macos")]
async fn on_main<R: Send + 'static>(
    operation: impl FnOnce(nsh_platform_macos::objc2::MainThreadMarker) -> Result<R, String>
    + Send
    + 'static,
) -> Result<R, String> {
    let (send, receive) = tokio::sync::oneshot::channel();
    dispatch2::DispatchQueue::main().exec_async(move || {
        let result = nsh_platform_macos::objc2::rc::autoreleasepool(|_| {
            nsh_platform_macos::objc2::MainThreadMarker::new()
                .ok_or_else(|| "native-dialog requires AppKit's main thread".to_owned())
                .and_then(operation)
        });
        let _ = send.send(result);
    });
    receive
        .await
        .map_err(|_| "native-dialog main-queue request was disposed".to_owned())?
}

impl Dialogs {
    #[cfg(target_os = "macos")]
    async fn state(&mut self) -> Result<NativeState, String> {
        if let Some(state) = &self.state {
            return Ok(state.clone());
        }
        let state = on_main(|main| {
            Ok(std::sync::Arc::new(dispatch2::MainThreadBound::new(
                std::cell::RefCell::new(macos::State::default()),
                main,
            )))
        })
        .await?;
        self.state = Some(state.clone());
        Ok(state)
    }

    pub(crate) async fn inspect(
        &mut self,
        renderer: &Renderer,
        answer: &str,
    ) -> Result<String, String> {
        let node = super::unique_target_for(answer, "native-dialog")?;
        let incarnation = renderer
            .current_incarnation(node)
            .ok_or("native-dialog owner is retired")?;
        crate::app::wait_for_commit().await?;
        if renderer.current_incarnation(node) != Some(incarnation) {
            return Err("native-dialog owner incarnation changed during commit".into());
        }
        let owner = Owner::capture(renderer, node)?;
        owner.check(renderer, None)?;
        self.owner.take();
        #[cfg(target_os = "macos")]
        {
            let state = self.state().await?;
            let identifier = owner.identifier.clone();
            let inspecting = state.clone();
            let dialog =
                on_main(move |main| inspecting.get(main).borrow_mut().inspect(&identifier, main))
                    .await?;
            if let Err(error) = owner.check(renderer, None) {
                on_main(move |main| {
                    state.get(main).borrow_mut().clear();
                    Ok(())
                })
                .await?;
                return Err(error);
            }
            if !dialog.is_null() {
                self.owner = Some(owner.clone());
            }
            Ok(json!({"ok":true,"op":"native-dialog","node":owner.node,
                "incarnation":owner.incarnation,"dialog":dialog})
            .to_string())
        }
        #[cfg(not(target_os = "macos"))]
        {
            Err("native-dialog inspection is currently supported only on macOS".into())
        }
    }

    pub(crate) async fn answer(
        &mut self,
        renderer: &Renderer,
        request: &str,
        admission: Option<&ApplicationMutations>,
    ) -> Result<String, String> {
        let (token, button) = answer_request(request)?;
        #[cfg(target_os = "macos")]
        {
            let owner = self
                .owner
                .as_ref()
                .ok_or("native-dialog owner lease is absent or consumed")?
                .clone();
            owner.check(renderer, admission)?;
            crate::app::wait_for_commit().await?;
            // Rc-owned admission stays on the engine thread, immediately before main dispatch.
            owner.check(renderer, admission)?;
            let state = self.state().await?;
            on_main(move |main| state.get(main).borrow_mut().answer(&token, &button)).await?;
            self.owner.take();
            Ok(
                json!({"ok":true,"op":"native-dialog-answer","node":owner.node,
                "incarnation":owner.incarnation,"activation":"native-controller","dispatched":true})
                .to_string(),
            )
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (renderer, admission, token, button);
            Err("native-dialog answers are currently supported only on macOS".into())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn inspection_and_answer_requests_are_typed_bounded_and_fail_closed() {
        assert_eq!(
            find(&json!({"op":"native-dialog","selector":"id:settings"})).unwrap(),
            json!({"op":"find","selector":"id:settings"}).to_string()
        );
        assert_eq!(
            answer_request(r#"{"op":"native-dialog-answer","token":"fresh","button":"Download"}"#)
                .unwrap(),
            ("fresh".into(), "Download".into())
        );
        for request in [
            json!({"op":"native-dialog","selector":""}),
            json!({"op":"native-dialog","selector":"x","extra":true}),
            json!({"op":"native-dialog-answer","token":"x","button":"x"}),
        ] {
            assert!(find(&request).is_err());
        }
        for request in [
            json!({"op":"native-dialog-answer","token":"","button":"x"}),
            json!({"op":"native-dialog-answer","token":"x","button":""}),
            json!({"op":"native-dialog-answer","token":"x","button":"x","extra":true}),
            json!({"op":"native-dialog-answer","token":"x","button":"x\n"}),
            json!({"op":"native-dialog-answer","token":"x".repeat(65),"button":"x"}),
        ] {
            assert!(answer_request(&request.to_string()).is_err());
        }
    }
}

#[cfg(test)]
mod owner_tests {
    use super::*;
    use crate::wire::Batch;
    use nsh_core::prelude::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;

    #[component]
    fn DialogOwnerGuards() -> impl IntoElement {
        let renderer = Renderer::new(|_, _| {});
        let patch = |generation, ops| {
            Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
        };
        renderer.apply(patch(1, json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":2,"kind":"button"},
            {"op":"set-prop","id":2,"property":"accessibility-identifier","value":"update-anchor"},
            {"op":"set-prop","id":2,"property":"enabled","value":false},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]))).unwrap();
        renderer.set_root(1).unwrap();
        let status = signal("waiting for dialog owner guard".to_owned());
        let checking = renderer.clone();
        spawn(async move {
            crate::app::wait_for_commit().await.unwrap();
            let owner = Owner::capture(&checking, 2).unwrap();
            assert!(
                owner.check(&checking, None).is_ok(),
                "disabled anchor is not activated"
            );
            let guard = ApplicationMutations::new(|| Err("update preparation holds input".into()));
            assert_eq!(
                owner.check(&checking, Some(&guard)).unwrap_err(),
                "update preparation holds input"
            );
            checking
                .apply(patch(
                    2,
                    json!([
                        {"op":"remove-child","parent":1,"child":2},
                        {"op":"drop-node","id":2}
                    ]),
                ))
                .unwrap();
            assert!(
                owner.check(&checking, None).is_err(),
                "retired exact owner cannot answer"
            );
            checking.apply(patch(3,json!([
                {"op":"create-node","id":2,"kind":"button"},
                {"op":"set-prop","id":2,"property":"accessibility-identifier","value":"update-anchor"},
                {"op":"insert-child","parent":1,"child":2,"index":0}
            ]))).unwrap();
            assert!(
                owner.check(&checking, None).is_err(),
                "same ID/label replacement is a different owner"
            );
            status.set("dialog owner retirement and admission guarded".into());
        });
        view()
            .child(renderer.element())
            .child(text(move || status.get()))
    }
    #[test]
    fn disabled_anchor_is_readable_but_retirement_replacement_and_quiescence_are_refused() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<DialogOwnerGuards>())).unwrap();
        app.wait_for("text:dialog owner retirement and admission guarded")
            .unwrap();
    }
}
