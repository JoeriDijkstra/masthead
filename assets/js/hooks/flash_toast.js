// LiveView hook: auto-dismisses a flash toast.
//
// The toast is visible on its own (CSS entrance animation), so this hook is
// purely about lifetime: a few seconds after it appears it clears the
// server-side flash via the built-in "lv:clear-flash" event, which animates
// it out and stops it reappearing on the next render. Clicking dismisses
// immediately. If a new message reuses the element, the timer restarts.
const DISMISS_MS = 4000
const LEAVE_MS = 220

export const FlashToast = {
  mounted() {
    this.key = this.el.dataset.key
    this.el.addEventListener("click", () => this.dismiss())
    this.arm()
  },

  updated() {
    this.el.classList.remove("is-leaving")
    this.arm()
  },

  destroyed() {
    clearTimeout(this.timer)
  },

  arm() {
    this.leaving = false
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.dismiss(), DISMISS_MS)
  },

  dismiss() {
    if (this.leaving) return
    this.leaving = true
    clearTimeout(this.timer)
    this.el.classList.add("is-leaving")
    setTimeout(() => this.pushEvent("lv:clear-flash", {key: this.key}), LEAVE_MS)
  },
}
