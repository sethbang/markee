// markee.sbang.dev — minimal client interactions.
// (1) Smooth-scroll for in-page anchor links.
// (2) Reveal-on-scroll for .reveal elements via IntersectionObserver.

(function () {
  "use strict";

  // Smooth scroll: native CSS scroll-behavior would work for most browsers,
  // but doing it here lets us also account for the sticky header height.
  document.querySelectorAll('a[href^="#"]').forEach((link) => {
    link.addEventListener("click", (e) => {
      const id = link.getAttribute("href").slice(1);
      if (!id) return;
      const target = document.getElementById(id);
      if (!target) return;
      e.preventDefault();
      const headerHeight = 64;
      const y = target.getBoundingClientRect().top + window.scrollY - headerHeight - 12;
      window.scrollTo({ top: y, behavior: "smooth" });
    });
  });

  // Reveal-on-scroll. Bail to "always visible" on browsers without
  // IntersectionObserver (which is essentially nobody in 2026, but the
  // fallback is free).
  if (!("IntersectionObserver" in window)) {
    document.querySelectorAll(".reveal").forEach((el) => el.classList.add("is-visible"));
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { rootMargin: "0px 0px -80px 0px", threshold: 0.05 }
  );

  document.querySelectorAll(".reveal").forEach((el) => observer.observe(el));
})();
