"use strict";

const shell = document.querySelector(".app-shell");

function titleCase(value) {
  return String(value || "unavailable")
    .replaceAll("-", " ")
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function valueOrDash(value, suffix = "") {
  return value === null || value === undefined ? "—" : `${value}${suffix}`;
}

function updateStatus(status) {
  const badge = document.querySelector("#overall-badge");
  badge.className = `status-badge status-${status.overall}`;
  badge.lastElementChild.textContent = titleCase(status.overall);

  document.querySelector("#speaker-name").textContent = status.audio.speaker_name;
  document.querySelector("#audio-state").textContent = titleCase(status.audio.state);
  document.querySelector("#audio-volume").textContent = valueOrDash(status.audio.volume, "%");
  document.querySelector("#audio-profile").textContent = String(status.audio.profile).toUpperCase();
  document.querySelector("#audio-delay").textContent = valueOrDash(status.audio.delay_ms, " ms");

  Object.entries(status.services).forEach(([name, state]) => {
    const card = document.querySelector(`[data-service="${name}"]`);
    if (!card) return;
    const icon = card.querySelector(".service-icon");
    icon.className = `service-icon status-${state}`;
    card.querySelector("p").textContent = titleCase(state);
  });

  document.querySelector("#network-hostname").textContent = status.network.hostname;
  document.querySelector("#network-address").textContent = status.network.address || "Unavailable";
  document.querySelector("#network-interface").textContent = status.network.interface || "Unavailable";
  document.querySelector("#network-connectivity").textContent = titleCase(status.network.connectivity);
  document.querySelector("#configuration-state").textContent = titleCase(status.configuration.state);
  document.querySelector("#configuration-message").textContent = status.configuration.message;
  document.querySelector("#last-update").textContent = `Updated ${new Date().toLocaleTimeString()}`;
}

async function refreshStatus() {
  try {
    const response = await fetch(shell.dataset.statusUrl, {cache: "no-store"});
    if (response.status === 401 || response.redirected) {
      window.location.reload();
      return;
    }
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    updateStatus(await response.json());
  } catch (error) {
    document.querySelector("#last-update").textContent = "Status refresh unavailable";
  }
}

if (shell) window.setInterval(refreshStatus, 5000);
