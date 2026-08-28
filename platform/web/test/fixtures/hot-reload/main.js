export function render() {
  document.querySelector("#js-value").textContent = "JavaScript HMR one"
}

render()

if (import.meta.hot) {
  import.meta.hot.accept((module) => module?.render())
}
