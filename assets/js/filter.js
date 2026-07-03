// Client-side list filtering, driven by Ramda.
//
// The LiveView renders every asset row with a `data-search` attribute; this hook
// shows/hides rows as the user types, without a server round-trip. Ramda expresses
// the predicate and set difference declaratively.
import * as R from "ramda"

export const Filter = {
  mounted() {
    this.input = this.el.querySelector("[data-filter-input]")
    this.empty = this.el.querySelector("[data-filter-empty]")
    this.apply = this.apply.bind(this)

    if (this.input) this.input.addEventListener("input", this.apply)
    this.apply()
  },

  updated() {
    // Re-apply after the LiveView patches the list (e.g. a new asset streamed in).
    this.apply()
  },

  destroyed() {
    if (this.input) this.input.removeEventListener("input", this.apply)
  },

  apply() {
    const query = R.toLower((this.input && this.input.value ? this.input.value : "").trim())
    const rows = Array.from(this.el.querySelectorAll("[data-search]"))

    const matches = (row) =>
      R.isEmpty(query) || R.includes(query, R.toLower(row.dataset.search || ""))

    const [shown, hidden] = R.partition(matches, rows)
    R.forEach((row) => (row.style.display = ""), shown)
    R.forEach((row) => (row.style.display = "none"), hidden)

    if (this.empty) this.empty.style.display = R.isEmpty(shown) ? "" : "none"
  },
}
