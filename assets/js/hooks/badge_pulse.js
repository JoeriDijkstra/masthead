// LiveView hook: briefly pulses the checklist badge whenever its count
// changes — an action was completed (count drops) or a new one arrived
// (count rises). Only fires when the number actually changes, so an
// unrelated re-render of the nav doesn't trigger it.
export const BadgePulse = {
  mounted() {
    this.last = this.el.textContent.trim()
  },

  updated() {
    const now = this.el.textContent.trim()
    if (now === this.last) return
    this.last = now

    this.el.classList.remove("badge-pulse")
    // Force a reflow so the animation restarts even on rapid consecutive updates.
    void this.el.offsetWidth
    this.el.classList.add("badge-pulse")
  },
}
