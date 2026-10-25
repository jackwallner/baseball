package com.jackwallner.baseball

import com.jackwallner.baseball.data.PendingUnlockAction
import org.junit.Assert.*
import org.junit.Test

class PendingUnlockActionTest {
    @Test fun entitlementWaitsForOfferDismissal() {
        val pending = PendingUnlockAction()
        var openedPicker = false
        pending.set { openedPicker = true }

        pending.resume(true)
        assertFalse(openedPicker)
        pending.dismiss(true, false)
        assertTrue(openedPicker)
    }

    @Test fun chosenSeasonResumesOnlyAfterEntitlementAndOnlyOnce() {
        val pending = PendingUnlockAction()
        var season = 2026
        var resumes = 0
        pending.set { season = 2023; resumes++ }

        pending.resume(false)
        assertEquals(2026, season)
        pending.dismiss(true, false)
        pending.resume(true)
        assertEquals(2023, season)
        assertEquals(1, resumes)
    }

    @Test fun dismissalWithoutPurchaseDoesNotResumeOnALaterUpgrade() {
        val pending = PendingUnlockAction()
        var openedComparison = false
        pending.set { openedComparison = true }

        pending.dismiss(false, false)
        pending.resume(true)
        assertFalse(openedComparison)
    }

    @Test fun pendingApprovalRetainsTheComparisonAfterDismissal() {
        val pending = PendingUnlockAction()
        var openedComparison = 0
        pending.set { openedComparison++ }

        pending.dismiss(false, true)
        pending.resume(false)
        assertEquals(0, openedComparison)
        pending.resume(true)
        pending.resume(true)
        assertEquals(1, openedComparison)
    }

    @Test fun chosenBoardIsPreserved() {
        val pending = PendingUnlockAction()
        var board = "Leaders"
        pending.set { board = "Best & Worst" }

        pending.dismiss(true, false)
        assertEquals("Best & Worst", board)
    }

    @Test fun latestLockedActionReplacesEarlierRequest() {
        val pending = PendingUnlockAction()
        var season = 2026
        pending.set { season = 2024 }
        pending.set { season = 2022 }

        pending.dismiss(true, false)
        assertEquals(2022, season)
    }

    @Test fun passivePitchClearsEarlierRequest() {
        val pending = PendingUnlockAction()
        var resumed = false
        pending.set { resumed = true }
        pending.set(null)
        pending.dismiss(true, false)
        assertFalse(resumed)
    }
}
