// The language switcher on every page saves the language picked, so the English home page knows not to
// send this browser to French or Spanish again (see the short script at the top of index.html). If the
// browser blocks storage, the links still work; the choice just isn't remembered.
document.addEventListener("click", function (event) {
  var link = event.target.closest ? event.target.closest(".lang-switch a[hreflang]") : null;
  if (!link) return;
  try {
    localStorage.setItem("mybaby-lang", link.getAttribute("hreflang"));
  } catch (e) {}
});
