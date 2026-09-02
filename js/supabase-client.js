/**
 * NIWALA — Supabase client bootstrap
 *
 * Fill in NIWALA_CONFIG below with your project's URL and anon key
 * (Project Settings → API in the Supabase dashboard). The anon key is
 * safe to expose client-side — it only grants what your Row Level
 * Security policies (see supabase/migrations/0001_init.sql) allow.
 *
 * NEVER put your service_role key or Stripe secret key here or
 * anywhere in frontend code.
 */

const NIWALA_CONFIG = {
  SUPABASE_URL: 'YOUR_SUPABASE_PROJECT_URL', // e.g. https://xxxxxxxx.supabase.co — from Project Settings → API
  SUPABASE_ANON_KEY: 'sb_publishable_dOCo-cAhFI4ja8mwZbPoEQ_sCBrj3EX',
};

// Loaded via the Supabase JS CDN script tag (see index.html <head>).
// Guarded so pages that don't need Supabase yet don't error out.
const supabaseClient = (window.supabase && NIWALA_CONFIG.SUPABASE_URL !== 'YOUR_SUPABASE_PROJECT_URL')
  ? window.supabase.createClient(NIWALA_CONFIG.SUPABASE_URL, NIWALA_CONFIG.SUPABASE_ANON_KEY)
  : null;

if (!supabaseClient) {
  console.warn('[NIWALA] Supabase is not configured yet — fill in js/supabase-client.js with your project URL and anon key.');
}
