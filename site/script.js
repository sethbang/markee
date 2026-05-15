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

  // Reveal-on-scroll. Base CSS keeps .reveal elements visible; we add
  // .reveal-armed to opt in to the hidden-then-fade animation, then
  // .is-visible on intersect. If IntersectionObserver isn't available, we
  // simply never arm — content stays visible.
  if (!("IntersectionObserver" in window)) return;

  const targets = document.querySelectorAll(".reveal");
  targets.forEach((el) => el.classList.add("reveal-armed"));

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

  targets.forEach((el) => observer.observe(el));
})();
