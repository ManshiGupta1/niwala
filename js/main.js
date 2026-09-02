/**
 * NIWALA — main.js
 * Shared, framework-free interactions used across public pages.
 * Dashboard-specific logic lives in js/customer.js, js/cook.js, etc.
 * as those panels are built.
 */

const NIWALA = (() => {
  function initMobileNav() {
    const toggle = document.querySelector('.nav-toggle');
    const links = document.querySelector('.nav-links');
    if (!toggle || !links) return;

    toggle.addEventListener('click', () => {
      const isOpen = links.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', String(isOpen));
    });
  }

  function initFollowButtons() {
    document.querySelectorAll('[data-follow-btn]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const nowFollowing = btn.classList.toggle('is-following');
        btn.setAttribute('aria-pressed', String(nowFollowing));
        btn.textContent = nowFollowing ? '♥ Following' : '♡ Follow';
        // TODO: replace with Supabase call once auth is wired up:
        // await supabase.from('follows').insert/delete(...)
      });
    });
  }

  function toast(message, { duration = 3200 } = {}) {
    const el = document.createElement('div');
    el.className = 'toast';
    el.setAttribute('role', 'status');
    el.textContent = message;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), duration);
  }

  function initCTAPlaceholders() {
    // Until auth pages exist, primary CTAs surface a friendly toast
    // instead of dead-ending on a 404.
    document.querySelectorAll('[data-coming-soon]').forEach((el) => {
      el.addEventListener('click', (e) => {
        if (el.tagName === 'A' && el.getAttribute('href') && el.getAttribute('href') !== '#') return;
        e.preventDefault();
        toast(el.dataset.comingSoon || 'This part of NIWALA is coming soon.');
      });
    });
  }

  function init() {
    initMobileNav();
    initFollowButtons();
    initCTAPlaceholders();
  }

  return { init, toast };
})();

document.addEventListener('DOMContentLoaded', NIWALA.init);
