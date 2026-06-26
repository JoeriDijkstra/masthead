// LiveView hook: Cmd/Ctrl+S saves the post/page wizard from ANY step, not
// just the content step. Attach to the stable wizard container.
//
// On the content step a real <form phx-submit="save"> exists, so we submit
// it directly — that captures the live editor value (CodeMirror mirrors every
// keystroke into the textarea immediately, with no debounce on the value).
// On the other steps there is no save form, so we push the "save" event and
// let the server save from the already-accumulated `draft` assign. The form's
// entity key ("post" | "page") comes from data-save-param.
export const SaveShortcut = {
  mounted() {
    this.handler = (e) => {
      const isSave = (e.metaKey || e.ctrlKey) && (e.key === "s" || e.key === "S")
      if (!isSave) return
      e.preventDefault()

      const saveForm = this.el.querySelector('form[phx-submit="save"]')
      if (saveForm) {
        saveForm.requestSubmit()
      } else {
        const param = this.el.dataset.saveParam || "post"
        this.pushEvent("save", {[param]: {}})
      }
    }
    window.addEventListener("keydown", this.handler, true)
  },

  destroyed() {
    window.removeEventListener("keydown", this.handler, true)
  },
}
