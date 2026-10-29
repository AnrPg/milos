# ADR-247: Saved cards, recurring charges and the payer's consent
Date: 2026-10-29
Status: Accepted

## Context
Boxes bill memberships every month. Charging a card without the payer is a
merchant-initiated transaction under PSD2: it needs a first payment with
strong customer authentication and the payer's agreement to later charges,
and the payer must be able to withdraw it. Charging more than agreed, or
again after a refund, would cause disputes.

## Decision
1. **Consent before the first payment.** When a member chooses to save the
   card, Palee shows a text naming the business (fiscal trade or legal name),
   the purpose and the largest amount per charge (the invoice's balance), in
   Greek or English. Paying needs `consent_accepted`; the consent record
   (version, language, SHA-256 of the exact text, time, IP, user agent,
   limit, currency) is stored on the intent and copied to the saved card.
   The wording is a draft for legal review (`2026-10-v1`).
2. **Saved cards** (`payment_methods`) keep only the provider token
   (encrypted), its digest, brand, last 4, expiry, status and the consent.
   They are created only after the provider confirms the first payment, and
   are deleted with the payer's account.
3. **Charges stay within consent.** A merchant charge must match the card's
   currency, not exceed its limit, and the card must be active and not
   expired. A higher price needs a new checkout.
4. **Autopay.** A member can mark one card for automatic payment of due open
   invoices. An hourly job (each business on its own local day) charges the
   balance with key `autopay:<invoice>:<balance>`, and never an invoice with
   a refunded payment.
5. **Dunning.** A declined charge is retried 1, 3 and 7 days after the first
   try, then fails; a provider outage is retried after 5, 30, 120 and 360
   minutes. Refused credentials or an uncertain request fail at once.
6. **Withdrawal.** The member (or staff) revokes a card at any time; it is
   never charged again.

## Consequences
- Renewal invoices are still created by Finance; autopay only pays what is
  due, so pricing stays in one place.
- Staff see failures and the decline reason per payment; reminders to the
  member reuse the existing payment-reminder flow.
