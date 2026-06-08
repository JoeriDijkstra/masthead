import { EditorView, basicSetup } from "codemirror"
import { EditorState } from "@codemirror/state"
import { keymap } from "@codemirror/view"
import { indentWithTab } from "@codemirror/commands"
import { markdown } from "@codemirror/lang-markdown"
import { html } from "@codemirror/lang-html"

function languageFor(name) {
  switch (name) {
    case "html":
      return html()
    case "markdown":
    case "blog":
    default:
      return markdown()
  }
}

// LiveView hook: turns a wrapper <div phx-hook="CodeEditor"> containing a
// <textarea> into a CodeMirror 6 editor with syntax highlighting. The original
// textarea is kept in the DOM (hidden) so the form submit and phx-debounce
// "input" event still flow through LiveView normally — every keystroke
// mirrors back to the textarea and dispatches an "input" event.
//
// The wrapper's data-language attribute selects the grammar ("markdown" |
// "html" | "blog"). To switch grammars, change the wrapper element's id
// (the hook will be re-mounted by LiveView).
export const CodeEditor = {
  mounted() {
    const textarea = this.el.querySelector("textarea")
    if (!textarea) return
    this.textarea = textarea
    textarea.style.display = "none"

    const lang = this.el.dataset.language || "markdown"

    const sync = EditorView.updateListener.of(update => {
      if (!update.docChanged) return
      const value = update.state.doc.toString()
      textarea.value = value
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    })

    this.view = new EditorView({
      state: EditorState.create({
        doc: textarea.value,
        extensions: [
          basicSetup,
          keymap.of([indentWithTab]),
          languageFor(lang),
          EditorView.lineWrapping,
          sync,
        ],
      }),
      parent: this.el,
    })

    // Server-driven edits (editor tools). The `id` in the payload scopes the
    // event to one editor so other CodeEditor instances ignore it. The sync
    // listener above mirrors the change back to the textarea automatically.
    this.handleEvent("editor_insert", ({id, text}) => {
      if (id && id !== this.el.id) return
      if (!this.view || !text) return
      const {from, to} = this.view.state.selection.main
      this.view.dispatch({
        changes: {from, to, insert: text},
        selection: {anchor: from + text.length},
      })
      this.view.focus()
    })

    this.handleEvent("editor_replace", ({id, text}) => {
      if (id && id !== this.el.id) return
      if (!this.view) return
      this.view.dispatch({
        changes: {from: 0, to: this.view.state.doc.length, insert: text || ""},
      })
      this.view.focus()
    })
  },

  destroyed() {
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
  },
}
