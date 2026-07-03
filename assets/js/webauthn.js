// WebAuthn / passkey ceremonies.
//
// These pages are rendered by plain controllers (not LiveView), because login
// completion has to happen in a plug/controller. So instead of LiveView hooks we
// self-initialize against well-known element ids when they're present on the page.
//
// Ramda is used for the small pure array transforms (credential descriptor lists)
// to keep the shape mapping declarative.
import * as R from "ramda"

// --- base64url <-> ArrayBuffer helpers ---

const bufToB64url = (buf) => {
  const bytes = new Uint8Array(buf)
  let str = ""
  for (const b of bytes) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

const b64urlToBuf = (value) => {
  const pad = value.length % 4 === 0 ? "" : "=".repeat(4 - (value.length % 4))
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/") + pad
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

// {type, id: <b64url>} -> {type, id: <ArrayBuffer>}
const decodeDescriptor = R.evolve({id: b64urlToBuf})
const decodeDescriptors = R.map(decodeDescriptor)

const supported = () =>
  typeof window.PublicKeyCredential !== "undefined" &&
  navigator.credentials &&
  typeof navigator.credentials.create === "function"

const setValue = (id, value) => {
  const el = document.getElementById(id)
  if (el) el.value = value
}

const setStatus = (el, message) => {
  if (el) el.textContent = message
}

// --- Second factor at login: navigator.credentials.get() ---

function initTwoFactor() {
  const root = document.getElementById("two-factor")
  if (!root) return

  const form = document.getElementById("two-factor-form")
  const status = document.getElementById("two-factor-status")
  const retry = document.getElementById("two-factor-retry")

  if (!supported()) {
    setStatus(status, "This browser doesn't support passkeys. Use a recovery code below.")
    return
  }

  const credentialIds = JSON.parse(root.dataset.credentialIds || "[]")

  const publicKey = {
    challenge: b64urlToBuf(root.dataset.challenge),
    rpId: root.dataset.rpId,
    timeout: 60000,
    userVerification: "preferred",
    allowCredentials: R.map(
      (id) => ({type: "public-key", id: b64urlToBuf(id)}),
      credentialIds
    ),
  }

  const run = async () => {
    setStatus(status, "Waiting for your passkey…")
    try {
      const credential = await navigator.credentials.get({publicKey})
      const response = credential.response
      setValue("assertion_credential_id", bufToB64url(credential.rawId))
      setValue("assertion_authenticator_data", bufToB64url(response.authenticatorData))
      setValue("assertion_signature", bufToB64url(response.signature))
      setValue("assertion_client_data_json", bufToB64url(response.clientDataJSON))
      form.requestSubmit()
    } catch (error) {
      console.error("passkey assertion failed", error)
      setStatus(status, "Passkey prompt was cancelled or failed. Tap “Use my passkey” to retry.")
    }
  }

  if (retry) retry.addEventListener("click", run)
  run()
}

// --- Enrollment: navigator.credentials.create() ---

function initRegistration() {
  const root = document.getElementById("passkey-register")
  if (!root) return

  const button = document.getElementById("passkey-register-btn")
  const labelInput = document.getElementById("passkey-label")
  const form = document.getElementById("passkey-form")
  const status = document.getElementById("passkey-status")

  if (!supported()) {
    setStatus(status, "This browser doesn't support passkeys.")
    if (button) button.disabled = true
    return
  }

  button.addEventListener("click", async () => {
    setStatus(status, "Follow your browser's prompt to create a passkey…")
    try {
      const options = await fetch("/users/passkeys/challenge", {
        headers: {accept: "application/json"},
        credentials: "same-origin",
      }).then((r) => r.json())

      const publicKey = {
        challenge: b64urlToBuf(options.challenge),
        rp: options.rp,
        user: {...options.user, id: b64urlToBuf(options.user.id)},
        pubKeyCredParams: options.pubKeyCredParams,
        excludeCredentials: decodeDescriptors(options.excludeCredentials || []),
        authenticatorSelection: options.authenticatorSelection,
        attestation: options.attestation,
        timeout: options.timeout,
      }

      const credential = await navigator.credentials.create({publicKey})
      const response = credential.response
      setValue("passkey_label_field", (labelInput && labelInput.value) || "")
      setValue("passkey_attestation_object", bufToB64url(response.attestationObject))
      setValue("passkey_client_data_json", bufToB64url(response.clientDataJSON))
      form.requestSubmit()
    } catch (error) {
      console.error("passkey registration failed", error)
      setStatus(status, "Couldn't create a passkey. Please try again.")
    }
  })
}

export function initWebAuthn() {
  initTwoFactor()
  initRegistration()
}
