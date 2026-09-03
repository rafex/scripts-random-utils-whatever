(function () {
  "use strict";

  var TOKEN_KEY = "rafex_firefoxos_sms_token";
  var token = null;
  var pending = null;
  var requestInFlight = false;
  var pairCard = document.getElementById("pair-card");
  var messageCard = document.getElementById("message-card");
  var linkedCard = document.getElementById("linked-card");
  var pairCode = document.getElementById("pair-code");
  var pairButton = document.getElementById("pair-button");
  var openButton = document.getElementById("open-button");
  var cancelButton = document.getElementById("cancel-button");
  var unlinkButton = document.getElementById("unlink-button");
  var globalStatus = document.getElementById("global-status");
  var messageStatus = document.getElementById("message-status");
  var messageData = document.getElementById("message-data");
  var messageRecipient = document.getElementById("message-recipient");
  var messageBody = document.getElementById("message-body");

  function setStatus(target, text) {
    target.textContent = text;
  }

  function request(method, path, data, callback) {
    var xhr = new XMLHttpRequest();
    xhr.open(method, path, true);
    xhr.setRequestHeader("Cache-Control", "no-cache");
    if (token) {
      xhr.setRequestHeader("Authorization", "Bearer " + token);
    }
    if (data !== null) {
      xhr.setRequestHeader("Content-Type", "application/json");
    }
    xhr.onreadystatechange = function () {
      var parsed = null;
      if (xhr.readyState !== 4) { return; }
      try { parsed = JSON.parse(xhr.responseText || "{}"); } catch (ignore) { parsed = {}; }
      callback(xhr.status, parsed);
    };
    xhr.onerror = function () { callback(0, {}); };
    xhr.send(data === null ? null : JSON.stringify(data));
  }

  function showLinked() {
    pairCard.className = "card hidden";
    linkedCard.className = "card";
    messageCard.className = "card";
  }

  function showUnlinked() {
    pairCard.className = "card";
    linkedCard.className = "card hidden";
    messageCard.className = "card hidden";
    pending = null;
  }

  function saveToken(value) {
    token = value;
    try { window.localStorage.setItem(TOKEN_KEY, value); } catch (ignore) {}
    showLinked();
    poll();
  }

  function clearToken() {
    token = null;
    try { window.localStorage.removeItem(TOKEN_KEY); } catch (ignore) {}
    showUnlinked();
    setStatus(globalStatus, "Aplicación desvinculada.");
  }

  function renderPending(message) {
    pending = message;
    if (!message) {
      messageData.className = "message-data hidden";
      openButton.disabled = true;
      cancelButton.disabled = true;
      setStatus(messageStatus, "No hay mensajes pendientes.");
      return;
    }
    messageData.className = "message-data";
    messageRecipient.textContent = message.recipient;
    messageBody.textContent = message.body;
    openButton.disabled = false;
    cancelButton.disabled = false;
    setStatus(messageStatus, "Revisa los datos y decide qué hacer.");
  }

  function poll() {
    if (!token || requestInFlight) { return; }
    requestInFlight = true;
    request("GET", "/api/v1/messages/pending", null, function (status, data) {
      requestInFlight = false;
      if (status === 401) {
        clearToken();
        setStatus(globalStatus, "La vinculación expiró o fue revocada.");
        return;
      }
      if (status !== 200) {
        setStatus(globalStatus, "No se pudo consultar la ThinkPad; se reintentará.");
        return;
      }
      renderPending(data.message || null);
      setStatus(globalStatus, "Última consulta realizada.");
    });
  }

  pairButton.onclick = function () {
    var code = pairCode.value;
    if (!/^[0-9]{8}$/.test(code)) {
      setStatus(globalStatus, "El código debe tener 8 dígitos.");
      return;
    }
    pairButton.disabled = true;
    request("POST", "/api/v1/pair/exchange", { code: code }, function (status, data) {
      pairButton.disabled = false;
      if (status === 200 && data.token) {
        pairCode.value = "";
        saveToken(data.token);
        setStatus(globalStatus, "ThinkPad vinculada correctamente.");
      } else {
        setStatus(globalStatus, "Código inválido, expirado o ya utilizado.");
      }
    });
  };

  openButton.onclick = function () {
    var activity;
    if (!pending) { return; }
    if (typeof MozActivity === "undefined") {
      setStatus(messageStatus, "Este Flame no ofrece la actividad histórica de Mensajes.");
      return;
    }
    try {
      activity = new MozActivity({
        name: "new",
        data: { type: "websms/sms", number: pending.recipient, body: pending.body }
      });
    } catch (error) {
      setStatus(messageStatus, "No se pudo abrir Mensajes.");
      return;
    }
    request("POST", "/api/v1/messages/" + encodeURIComponent(pending.id) + "/presented", null, function (status) {
      if (status === 200) {
        renderPending(null);
        setStatus(globalStatus, "Mensajes fue abierto; confirma el envío en el teléfono.");
      } else {
        setStatus(globalStatus, "Mensajes se abrió, pero no se pudo actualizar la cola.");
      }
    });
  };

  cancelButton.onclick = function () {
    if (!pending) { return; }
    request("POST", "/api/v1/messages/" + encodeURIComponent(pending.id) + "/cancel", null, function (status) {
      if (status === 200) {
        renderPending(null);
        setStatus(globalStatus, "Mensaje cancelado sin abrir Mensajes.");
      } else {
        setStatus(globalStatus, "No se pudo cancelar el mensaje.");
      }
    });
  };

  unlinkButton.onclick = clearToken;

  try { token = window.localStorage.getItem(TOKEN_KEY); } catch (ignore) { token = null; }
  if (token) {
    showLinked();
    poll();
  } else {
    showUnlinked();
  }
  window.setInterval(poll, 5000);
}());
