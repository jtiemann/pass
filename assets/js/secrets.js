// Reveal / copy handling for encrypted secrets, driven by RxJS.
//
// The server never puts plaintext secrets in the rendered DOM. Instead, on an
// explicit "reveal"/"copy" the LiveView pushes the value as an event payload to
// this hook, which injects it client-side and schedules an automatic clear:
//   * a revealed secret re-masks itself after AUTO_HIDE_MS
//   * a copied secret is wiped from the clipboard after AUTO_CLEAR_MS, with a
//     live countdown
//
// RxJS gives us cancellable timers/countdowns: re-revealing or re-copying the
// same credential cancels the previous schedule via a per-id Subject.
import {timer, interval, Subject} from "rxjs"
import {take, takeUntil, map} from "rxjs/operators"

const AUTO_HIDE_MS = 20000
const AUTO_CLEAR_MS = 20000
const MASK = "••••••••"

export const Secrets = {
  mounted() {
    // Per-credential-id cancellation signals, so a new action supersedes the old.
    this.cancels = new Map()

    this.handleEvent("secret:show", ({id, value}) => this.reveal(id, value))
    this.handleEvent("secret:copy", ({id, value}) => this.copy(id, value))
  },

  destroyed() {
    this.cancels.forEach((subject) => subject.next())
  },

  cancelFor(id) {
    let subject = this.cancels.get(id)
    if (subject) {
      subject.next() // cancel any in-flight timer for this id
    } else {
      subject = new Subject()
      this.cancels.set(id, subject)
    }
    return subject
  },

  reveal(id, value) {
    const el = document.getElementById(`secret-value-${id}`)
    if (!el) return
    const cancel = this.cancelFor(id)

    el.textContent = value && value.length ? value : "(none)"
    el.dataset.revealed = "true"

    timer(AUTO_HIDE_MS)
      .pipe(takeUntil(cancel))
      .subscribe(() => {
        el.textContent = MASK
        delete el.dataset.revealed
      })
  },

  async copy(id, value) {
    const status = document.getElementById(`secret-status-${id}`)
    const cancel = this.cancelFor(id)

    try {
      await navigator.clipboard.writeText(value || "")
    } catch (_e) {
      if (status) status.textContent = "Couldn't access the clipboard."
      return
    }

    const seconds = Math.round(AUTO_CLEAR_MS / 1000)

    // Countdown, then wipe the clipboard.
    interval(1000)
      .pipe(
        take(seconds),
        map((elapsed) => seconds - elapsed - 1),
        takeUntil(cancel)
      )
      .subscribe({
        next: (remaining) => {
          if (status) status.textContent = `Copied — clears in ${remaining + 1}s`
        },
        complete: () => {
          navigator.clipboard.writeText("").catch(() => {})
          if (status) status.textContent = "Clipboard cleared."
        },
      })
  },
}
