$(function () {
  // dirty setTimeout Hack to get first log-tab displayed
  window.setTimeout(function() {
    $('.nav.nav-tabs a[data-toggle]').first().tab('show');
  }, 1000);
});