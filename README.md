# NIWALA

**Ghar ka khana. Apne sheher ke cooks se.**

A hyperlocal marketplace connecting customers with home cooks who control
their own menu, availability, and daily cooking capacity — and delivery
partners who choose flexible local gigs.

> Cook what you love. Sell what you can. Earn on your terms.

## Status

🚧 **Stage 1 of the build** — brand/design system, landing page, and full
database schema. See [Roadmap](#roadmap) below for what's next.

## Tech stack

- **Frontend:** HTML5, CSS3, vanilla JavaScript (modular, component-based structure — no framework)
- **Backend:** [Supabase](https://supabase.com) — Postgres, Auth, Row Level Security, Storage
- **Payments:** [Stripe](https://stripe.com) — Checkout for customer payments, Stripe Connect for cook/delivery-partner payouts (architecture in place, live integration pending)

## Project structure

```
niwala/
├── index.html              # Landing page
├── css/
│   ├── variables.css        # Design tokens (color, type, spacing)
│   ├── base.css              # Reset + global element styles
│   ├── components.css        # Shared components (nav, cards, buttons…)
│   └── landing.css           # Landing-page-specific styles
├── js/
│   ├── main.js                # Shared interactions (nav, follow buttons, toasts)
│   └── supabase-client.js     # Supabase bootstrap — fill in your project keys here
├── pages/
│   ├── auth/                  # Login / signup (role selection)
│   ├── customer/               # Customer dashboard
│   ├── cook/                    # Cook dashboard
│   ├── delivery/                 # Delivery partner dashboard
│   └── admin/                     # Admin dashboard
├── supabase/
│   └── migrations/
│       └── 0001_init.sql       # Full schema: users, cooks, dishes, capacity,
│                                 orders, payments, earnings ledgers, RLS policies
└── docs/
```

## Getting started

1. **Clone the repo** and open `index.html` in a browser, or serve it with any
   static server (e.g. `npx serve .`) — there's no build step.
2. **Set up Supabase:**
   - Create a project at [supabase.com/dashboard](https://supabase.com/dashboard)
   - In the SQL Editor, run `supabase/migrations/0001_init.sql`
   - Copy your Project URL and anon key from **Project Settings → API**
   - Paste them into `js/supabase-client.js`
3. **Add the Supabase JS SDK** to any page that needs it:
   ```html
   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
   <script src="js/supabase-client.js"></script>
   ```

## Core business rule: capacity

Every cook sets a maximum number of meals they're willing to prepare per
day/meal-slot. Once accepted orders reach that number, the system marks the
cook **SOLD OUT FOR TODAY** and blocks further orders — capacity is never
bypassable from the client, it's enforced by the `cook_capacity` table and
Row Level Security policies (and will be double-checked server-side once
order-placement logic lands).

## Financial separation

Customer payments, cook earnings, delivery gig payouts, and NIWALA's
platform commission are always kept in separate ledgers
(`payments`, `cook_earnings`, `delivery_earnings`) — never mixed, and never
calculated client-side. See `supabase/migrations/0001_init.sql`.

## Roadmap

- [x] Design system + landing page
- [x] Database schema + RLS policies
- [ ] Auth pages (role-based signup/login)
- [ ] Customer dashboard (browse, follow, order, track, review)
- [ ] Cook dashboard (menu, capacity, availability, orders, earnings)
- [ ] Delivery partner dashboard (job feed, delivery flow, earnings)
- [ ] Admin dashboard (users, verification, orders, payments)
- [ ] Stripe Checkout + webhook handler (backend)
- [ ] Stripe Connect onboarding for cooks/delivery partners

## Security notes

- Stripe secret key, webhook secret, and Supabase service_role key must
  **never** appear in frontend code — only the Supabase anon key and Stripe
  publishable key are safe to expose client-side.
- All authoritative financial calculations happen server-side.
- Row Level Security is enabled on every table; see policies at the bottom
  of the migration file.
