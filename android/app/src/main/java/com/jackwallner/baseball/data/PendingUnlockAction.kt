package com.jackwallner.baseball.data

/** Retains the chosen action through plan selection and pending approval. */
class PendingUnlockAction {
    private var action: (() -> Unit)? = null
    private var offerIsPresented = false

    fun set(action: (() -> Unit)?) {
        this.action = action
        offerIsPresented = action != null
    }

    fun resume(isPro: Boolean) {
        if (!isPro || offerIsPresented) return
        val action = this.action
        this.action = null
        action?.invoke()
    }

    fun dismiss(isPro: Boolean, purchasePending: Boolean) {
        offerIsPresented = false
        resume(isPro)
        if (!purchasePending) action = null
    }
}
