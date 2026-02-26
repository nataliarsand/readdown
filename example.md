# Sprint Planning — Week of Feb 24

## Overview

We're entering **Phase 2** of the redesign. The goal this week is to finish the checkout flow and start on the notification system. Design handoff is Thursday.

---

## Tasks

### Checkout Flow

1. Update cart summary component with new pricing layout
   Includes discount codes, tax breakdown, and shipping estimate
2. Add Stripe payment intent integration
   Use the existing `PaymentService` wrapper — don't call the API directly
3. Build order confirmation page
   Pull the email template from Figma, match it 1:1
4. Write tests for edge cases
   Empty cart, expired session, failed payment, partial refund

### Notification System

- [ ] Define notification types and priority levels
- [ ] Design the toast component (max 3 visible at once)
- [ ] Build notification store with read/unread state
- [x] Research push notification options for macOS
- [x] Set up Firebase Cloud Messaging project

---

## Tech Notes

Use the `useToast()` hook for triggering notifications from anywhere:

```typescript
const toast = useToast()
toast.show({
  title: "Payment received",
  type: "success",
  duration: 5000
})
```

For the checkout API, the response format looks like this:

```json
{
  "order_id": "ord_8x92mf",
  "status": "confirmed",
  "total": 149.99,
  "currency": "USD"
}
```

---

## Team

| Name | Role | Focus this week |
|------|------|-----------------|
| Ana | Frontend | Checkout UI + tests |
| Marcus | Backend | Payment integration |
| Priya | Design | Notification specs |
| Leo | QA | Regression suite |

---

## Reminders

> Don't forget: demo to stakeholders is **Friday at 3pm**. Keep the staging branch clean.

- Standup is at 9:30am as usual
- Design review moved to **Wednesday 2pm**
- Leo is out Thursday — run smoke tests before EOD Wednesday
