-- =========================================================
-- NIWALA — Initial schema
-- Run this in Supabase SQL Editor (or `supabase db push`).
-- Depends on Supabase's built-in `auth.users` table for identity.
-- =========================================================

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------
create type user_role as enum ('customer', 'cook', 'delivery_partner', 'admin');

create type verification_status as enum ('pending', 'approved', 'rejected');

create type order_status as enum (
  'placed', 'accepted', 'preparing', 'ready_for_pickup',
  'picked_up', 'out_for_delivery', 'delivered',
  'rejected', 'cancelled', 'payment_failed'
);

create type payment_method as enum ('upi', 'card', 'cod', 'other_stripe');

create type payment_status as enum (
  'pending', 'processing', 'paid', 'failed',
  'expired', 'cancelled', 'refunded'
);

create type settlement_status as enum (
  'pending', 'available', 'processing', 'settled', 'refunded', 'reversed'
);

create type payout_status as enum ('pending', 'available', 'processing', 'paid', 'reversed');

create type delivery_status as enum (
  'assigned', 'navigating_to_cook', 'arrived_at_pickup',
  'picked_up', 'navigating_to_customer', 'delivered'
);

create type stripe_connect_status as enum (
  'not_connected', 'pending_verification', 'restricted', 'active'
);

create type meal_slot as enum ('breakfast', 'lunch', 'dinner');

-- ---------------------------------------------------------
-- USERS (extends auth.users)
-- ---------------------------------------------------------
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  role user_role not null,
  full_name text not null,
  phone text,
  avatar_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.addresses (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  label text,                       -- 'Home', 'Work', etc.
  line1 text not null,
  line2 text,
  city text not null,
  state text,
  pincode text,
  latitude double precision,
  longitude double precision,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- ROLE PROFILES
-- ---------------------------------------------------------
create table public.customers (
  user_id uuid primary key references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.cooks (
  user_id uuid primary key references public.users(id) on delete cascade,
  kitchen_name text not null,
  bio text,
  cuisine text,
  cover_image_url text,
  latitude double precision,
  longitude double precision,
  verification_status verification_status not null default 'pending',
  verified_at timestamptz,
  rating_avg numeric(3,2) not null default 0,
  rating_count integer not null default 0,
  is_paused boolean not null default false,   -- manual "pause orders" toggle
  stripe_account_id text,
  stripe_connect_status stripe_connect_status not null default 'not_connected',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.delivery_partners (
  user_id uuid primary key references public.users(id) on delete cascade,
  vehicle_type text,
  license_number text,
  is_available boolean not null default false,
  latitude double precision,
  longitude double precision,
  rating_avg numeric(3,2) not null default 0,
  stripe_account_id text,
  stripe_connect_status stripe_connect_status not null default 'not_connected',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- MENU / DISHES
-- ---------------------------------------------------------
create table public.dishes (
  id uuid primary key default uuid_generate_v4(),
  cook_id uuid not null references public.cooks(user_id) on delete cascade,
  name text not null,
  description text,
  price numeric(10,2) not null check (price >= 0),
  category text,
  image_url text,
  is_veg boolean not null default true,
  prep_time_minutes integer,
  daily_capacity integer not null default 0 check (daily_capacity >= 0),
  quantity_remaining_today integer not null default 0 check (quantity_remaining_today >= 0),
  is_available_today boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_dishes_cook on public.dishes(cook_id);

-- ---------------------------------------------------------
-- COOK AVAILABILITY & CAPACITY (core NIWALA differentiator)
-- ---------------------------------------------------------
create table public.cook_availability (
  id uuid primary key default uuid_generate_v4(),
  cook_id uuid not null references public.cooks(user_id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6), -- 0=Sunday
  meal_slot meal_slot not null,
  is_working boolean not null default true,
  unique (cook_id, day_of_week, meal_slot)
);

create table public.cook_capacity (
  id uuid primary key default uuid_generate_v4(),
  cook_id uuid not null references public.cooks(user_id) on delete cascade,
  date date not null,
  meal_slot meal_slot not null,
  max_capacity integer not null check (max_capacity >= 0),
  accepted_orders integer not null default 0 check (accepted_orders >= 0),
  created_at timestamptz not null default now(),
  unique (cook_id, date, meal_slot)
);

-- remaining capacity is derived, not stored, to avoid drift:
create view public.cook_capacity_status as
  select
    id, cook_id, date, meal_slot, max_capacity, accepted_orders,
    greatest(max_capacity - accepted_orders, 0) as remaining_capacity,
    (accepted_orders >= max_capacity) as is_sold_out
  from public.cook_capacity;

-- ---------------------------------------------------------
-- FOLLOWS
-- ---------------------------------------------------------
create table public.follows (
  customer_id uuid not null references public.customers(user_id) on delete cascade,
  cook_id uuid not null references public.cooks(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (customer_id, cook_id)
);

-- ---------------------------------------------------------
-- ORDERS
-- ---------------------------------------------------------
create table public.orders (
  id uuid primary key default uuid_generate_v4(),
  order_code text not null unique,              -- e.g. NW10245
  customer_id uuid not null references public.customers(user_id),
  cook_id uuid not null references public.cooks(user_id),
  delivery_address_id uuid references public.addresses(id),
  status order_status not null default 'placed',
  payment_method payment_method not null,
  subtotal_amount numeric(10,2) not null,
  delivery_fee numeric(10,2) not null default 0,
  total_amount numeric(10,2) not null,
  requested_meal_slot meal_slot,
  requested_delivery_time timestamptz,
  placed_at timestamptz not null default now(),
  accepted_at timestamptz,
  rejected_at timestamptz,
  cancelled_at timestamptz,
  delivered_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_orders_customer on public.orders(customer_id);
create index idx_orders_cook on public.orders(cook_id);
create index idx_orders_status on public.orders(status);

create table public.order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id) on delete cascade,
  dish_id uuid not null references public.dishes(id),
  dish_name_snapshot text not null,     -- preserved even if dish is edited later
  unit_price numeric(10,2) not null,
  quantity integer not null check (quantity > 0),
  line_total numeric(10,2) not null
);

create index idx_order_items_order on public.order_items(order_id);

-- ---------------------------------------------------------
-- DELIVERIES
-- ---------------------------------------------------------
create table public.deliveries (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  delivery_partner_id uuid references public.delivery_partners(user_id),
  status delivery_status not null default 'assigned',
  pickup_lat double precision,
  pickup_lng double precision,
  drop_lat double precision,
  drop_lng double precision,
  distance_km numeric(6,2),
  gig_amount numeric(10,2) not null,
  bonus_amount numeric(10,2) not null default 0,
  accepted_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now()
);

create index idx_deliveries_partner on public.deliveries(delivery_partner_id);

-- ---------------------------------------------------------
-- PAYMENTS  (Stripe-backed; see docs/stripe-integration.md)
-- ---------------------------------------------------------
create table public.payments (
  payment_id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_id uuid not null references public.customers(user_id),
  amount numeric(10,2) not null,
  currency text not null default 'inr',
  payment_method payment_method not null,
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  stripe_customer_id text,
  payment_status payment_status not null default 'pending',
  transaction_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  paid_at timestamptz
);

create unique index idx_payments_stripe_session on public.payments(stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;

-- Stripe webhook idempotency log — prevents double-processing retried events.
create table public.stripe_events_log (
  stripe_event_id text primary key,
  event_type text not null,
  processed_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- EARNINGS LEDGERS (kept separate from customer payments)
-- ---------------------------------------------------------
create table public.cook_earnings (
  earning_id uuid primary key default uuid_generate_v4(),
  cook_id uuid not null references public.cooks(user_id),
  order_id uuid not null references public.orders(id),
  gross_food_amount numeric(10,2) not null,
  platform_commission numeric(10,2) not null,
  payment_processing_fee numeric(10,2) not null default 0,
  adjustments numeric(10,2) not null default 0,
  net_amount numeric(10,2) not null,
  settlement_status settlement_status not null default 'pending',
  stripe_transfer_id text,
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create table public.delivery_earnings (
  earning_id uuid primary key default uuid_generate_v4(),
  delivery_partner_id uuid not null references public.delivery_partners(user_id),
  delivery_id uuid not null references public.deliveries(id),
  order_id uuid not null references public.orders(id),
  gig_amount numeric(10,2) not null,
  bonus numeric(10,2) not null default 0,
  adjustment numeric(10,2) not null default 0,
  net_amount numeric(10,2) not null,
  payout_status payout_status not null default 'pending',
  stripe_transfer_id text,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

-- Platform-wide commission rate, configurable by Admin (not hard-coded).
create table public.platform_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
insert into public.platform_settings (key, value)
  values ('commission_percent', '10'::jsonb);

-- ---------------------------------------------------------
-- REVIEWS
-- ---------------------------------------------------------
create table public.reviews (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null unique references public.orders(id),
  customer_id uuid not null references public.customers(user_id),
  cook_id uuid not null references public.cooks(user_id),
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------
create table public.notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  type text not null,          -- e.g. 'order_accepted', 'new_follower'
  title text not null,
  body text,
  is_read boolean not null default false,
  related_order_id uuid references public.orders(id),
  created_at timestamptz not null default now()
);

create index idx_notifications_user on public.notifications(user_id, is_read);

-- ---------------------------------------------------------
-- ADMIN ACTIONS (audit trail)
-- ---------------------------------------------------------
create table public.admin_actions (
  id uuid primary key default uuid_generate_v4(),
  admin_id uuid not null references public.users(id),
  action_type text not null,      -- e.g. 'cook_verified', 'user_suspended'
  target_table text,
  target_id uuid,
  notes text,
  created_at timestamptz not null default now()
);

-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================

alter table public.users enable row level security;
alter table public.addresses enable row level security;
alter table public.customers enable row level security;
alter table public.cooks enable row level security;
alter table public.delivery_partners enable row level security;
alter table public.dishes enable row level security;
alter table public.cook_availability enable row level security;
alter table public.cook_capacity enable row level security;
alter table public.follows enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.deliveries enable row level security;
alter table public.payments enable row level security;
alter table public.cook_earnings enable row level security;
alter table public.delivery_earnings enable row level security;
alter table public.reviews enable row level security;
alter table public.notifications enable row level security;
alter table public.admin_actions enable row level security;

-- Helper: is the current user an admin?
create or replace function public.is_admin() returns boolean as $$
  select exists (
    select 1 from public.users where id = auth.uid() and role = 'admin'
  );
$$ language sql stable security definer;

-- USERS: everyone can read basic public profile fields via a view in
-- production; for MVP, a user can read/update only their own row, admins read all.
create policy "users_select_own_or_admin" on public.users
  for select using (id = auth.uid() or public.is_admin());
create policy "users_update_own" on public.users
  for update using (id = auth.uid());

-- ADDRESSES: owner only.
create policy "addresses_owner" on public.addresses
  for all using (user_id = auth.uid());

-- COOKS: public read (menu browsing is anonymous-friendly); only the
-- cook themself or admin can write.
create policy "cooks_public_read" on public.cooks
  for select using (true);
create policy "cooks_owner_write" on public.cooks
  for update using (user_id = auth.uid() or public.is_admin());
create policy "cooks_owner_insert" on public.cooks
  for insert with check (user_id = auth.uid());

-- DELIVERY PARTNERS: partner sees/edits own row; admin sees all.
create policy "delivery_partners_owner" on public.delivery_partners
  for all using (user_id = auth.uid() or public.is_admin());

-- DISHES: public read; only owning cook (or admin) writes.
create policy "dishes_public_read" on public.dishes
  for select using (true);
create policy "dishes_cook_write" on public.dishes
  for all using (cook_id = auth.uid() or public.is_admin());

-- AVAILABILITY / CAPACITY: public read (needed for "sold out" UI);
-- only owning cook or admin writes.
create policy "availability_public_read" on public.cook_availability
  for select using (true);
create policy "availability_cook_write" on public.cook_availability
  for all using (cook_id = auth.uid() or public.is_admin());

create policy "capacity_public_read" on public.cook_capacity
  for select using (true);
create policy "capacity_cook_write" on public.cook_capacity
  for all using (cook_id = auth.uid() or public.is_admin());

-- FOLLOWS: customer manages their own follow list; cook can see their followers.
create policy "follows_customer_manage" on public.follows
  for all using (customer_id = auth.uid());
create policy "follows_cook_read" on public.follows
  for select using (cook_id = auth.uid() or public.is_admin());

-- ORDERS: visible to the customer who placed it, the cook who received
-- it, the assigned delivery partner, and admins.
create policy "orders_participants_read" on public.orders
  for select using (
    customer_id = auth.uid()
    or cook_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.deliveries d
      where d.order_id = orders.id and d.delivery_partner_id = auth.uid()
    )
  );
create policy "orders_customer_insert" on public.orders
  for insert with check (customer_id = auth.uid());
create policy "orders_cook_update" on public.orders
  for update using (cook_id = auth.uid() or public.is_admin());

-- ORDER ITEMS: follow parent order's visibility.
create policy "order_items_via_order" on public.order_items
  for select using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (o.customer_id = auth.uid() or o.cook_id = auth.uid() or public.is_admin())
    )
  );

-- DELIVERIES: visible to assigned partner, the order's customer/cook, admin.
create policy "deliveries_participants_read" on public.deliveries
  for select using (
    delivery_partner_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.orders o
      where o.id = deliveries.order_id
        and (o.customer_id = auth.uid() or o.cook_id = auth.uid())
    )
  );
create policy "deliveries_partner_update" on public.deliveries
  for update using (delivery_partner_id = auth.uid() or public.is_admin());

-- PAYMENTS: customer sees own payments; admin sees all. Writes happen
-- only via the backend service role (Stripe webhook handler), never
-- directly from the client.
create policy "payments_customer_read" on public.payments
  for select using (customer_id = auth.uid() or public.is_admin());

-- EARNINGS: cook/delivery partner see only their own ledger; admin sees all.
create policy "cook_earnings_owner_read" on public.cook_earnings
  for select using (cook_id = auth.uid() or public.is_admin());
create policy "delivery_earnings_owner_read" on public.delivery_earnings
  for select using (delivery_partner_id = auth.uid() or public.is_admin());

-- REVIEWS: public read; only the reviewing customer writes.
create policy "reviews_public_read" on public.reviews
  for select using (true);
create policy "reviews_customer_write" on public.reviews
  for insert with check (customer_id = auth.uid());

-- NOTIFICATIONS: owner only.
create policy "notifications_owner" on public.notifications
  for all using (user_id = auth.uid());

-- ADMIN ACTIONS: admin only.
create policy "admin_actions_admin_only" on public.admin_actions
  for all using (public.is_admin());
