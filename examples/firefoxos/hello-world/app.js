(function () {
  "use strict";

  var button = document.getElementById("hello-button");
  var status = document.getElementById("status");
  var interactions = 0;

  button.addEventListener("click", function () {
    interactions += 1;
    status.textContent = "¡Hola desde Firefox OS! Interacciones: " + interactions;
  });
}());
