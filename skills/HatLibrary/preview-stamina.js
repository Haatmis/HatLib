// preview-stamina.js — aperçu de l'affichage d'endurance (StaminaService).
//
// Chargé à la demande par configurator.html quand le .luau porte l'annotation
// « 🎬 APERÇU: stamina/hud ». Sans dépendance.
//
// Ce que la scène montre : un écran de jeu factice, un personnage dedans, et la
// jauge dessinée exactement dans la forme, la position et le style réglés — à
// l'écran, au-dessus du personnage, ou les deux. La valeur monte et descend en
// boucle pour qu'on voie le remplissage, le seuil bas, le fondu et le clignotement.
//
// Contrat attendu par le configurateur :
//   mount(canvas, { get, scenario }) -> { cameras, camera, setCamera, sync,
//                                         setPlaying, replay, destroy }

// Les « caméras » sont ici des formats d'écran : c'est ce qui compte pour juger
// un ancrage — une barre bien placée en 16:9 peut sortir du cadre en mobile.
export const cameras = [
  { id: "wide", label: "16:9", aspect: 16 / 9 },
  { id: "ultra", label: "21:9", aspect: 21 / 9 },
  { id: "classic", label: "4:3", aspect: 4 / 3 },
  { id: "mobile", label: "Mobile", aspect: 10 / 16 },
];

// Résolution de référence : les pixels réglés dans le prefab sont ceux d'un
// écran 1280 de large. On met l'aperçu à la même échelle pour que 220 px de
// barre occupent la même part d'écran ici et en jeu.
const REF_WIDTH = 1280;
const STUDS_TO_PX = 26; // conversion des tailles studs du billboard en pixels d'aperçu

const NOOB = { head: "#F5CD30", torso: "#0D69AC", arm: "#F5CD30", leg: "#2C5E2E" };

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

const ANCHORS = {
  HautGauche: [0, 0], HautCentre: [0.5, 0], HautDroite: [1, 0],
  MilieuGauche: [0, 0.5], Centre: [0.5, 0.5], MilieuDroite: [1, 0.5],
  BasGauche: [0, 1], BasCentre: [0.5, 1], BasDroite: [1, 1],
};

function roundRect(ctx, x, y, w, h, r) {
  const rr = Math.min(r, Math.abs(w) / 2, Math.abs(h) / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x, y + h, rr);
  ctx.arcTo(x, y + h, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
}

function withAlpha(hex, alpha) {
  const n = parseInt(String(hex).slice(1), 16);
  if (!Number.isFinite(n)) return `rgba(255,255,255,${alpha})`;
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${alpha})`;
}

export function mount(canvas, api) {
  const ctx = canvas.getContext("2d");
  const get = (name, def) => {
    const v = api.get(name);
    return v === undefined || v === null || v === "" ? def : v;
  };
  const num = (name, def) => {
    const v = Number(get(name, def));
    return Number.isFinite(v) ? v : def;
  };
  const bool = (name, def) => {
    const v = get(name, def);
    return v === true || v === "true";
  };
  const str = (name, def) => String(get(name, def));

  let camId = "wide";
  let aspect = cameras[0].aspect;
  let playing = true, raf = 0, last = 0, dpr = 1, W = 0, H = 0;
  let sim = null;

  function reset() {
    sim = { t: 0, value: num("STAMINA_MAX", 100), sinceSpend: 99, draining: false, lockedFor: 0, shown: 0 };
  }
  reset();

  // ---------------------------------------------------------- simulation
  // Un joueur qui sprinte par à-coups : deux salves, puis on laisse la jauge
  // remonter. La dépense est fixée à 25/s — le coût réel appartient au sprint,
  // ce qui se règle ici c'est le maximum, la régénération et l'affichage.
  const SIM_COST = 25;

  function step(dt) {
    const max = num("STAMINA_MAX", 100);
    const regen = num("REGEN_RATE", 15);
    const delay = num("REGEN_DELAY", 1);
    const lockout = num("EMPTY_LOCKOUT", 0);

    sim.t += dt;
    const phase = sim.t % 9;
    sim.draining = (phase > 0.6 && phase < 4.2) || (phase > 5.4 && phase < 6.4);

    if (sim.lockedFor > 0) {
      sim.lockedFor = Math.max(0, sim.lockedFor - dt);
      sim.draining = false;
    }

    if (sim.draining && sim.value > 0) {
      sim.value = clamp(sim.value - SIM_COST * dt, 0, max);
      sim.sinceSpend = 0;
      if (sim.value <= 0 && lockout > 0) sim.lockedFor = lockout;
    } else {
      sim.sinceSpend += dt;
      if (sim.value < max && sim.sinceSpend >= delay) {
        sim.value = clamp(sim.value + regen * dt, 0, max);
      }
    }
    if (sim.value > max) sim.value = max;

    // Visibilité : la même règle que dans le prefab, fondu compris.
    const ratio = max > 0 ? sim.value / max : 0;
    const showWhen = str("SHOW_WHEN", "Incomplet");
    let want =
      showWhen === "Toujours" ? 1 :
      showWhen === "EnUsage" ? (sim.draining || ratio < 0.999 ? 1 : 0) :
      ratio < 0.999 ? 1 : 0;
    if (bool("FLASH_ON_EMPTY", true) && ratio <= 0.001) {
      want = (sim.t % 0.5) < 0.25 ? 1 : 0;
    }
    const fade = num("FADE_TIME", 0.3);
    sim.shown = fade <= 0 ? want : sim.shown + (want - sim.shown) * clamp(dt / fade, 0, 1);
  }

  // ------------------------------------------------------------- la jauge
  // Un seul dessinateur pour les deux hôtes : on lui donne un rectangle, il
  // remplit la forme demandée dedans. C'est ce qui garantit que la barre
  // au-dessus du personnage est bien la même que celle de l'écran.
  function drawWidget(mode, x, y, w, h, ratio, scale, alpha) {
    if (alpha <= 0.004) return;
    const fill = str("FILL_COLOR", "#5B8CFF");
    const low = str("FILL_COLOR_LOW", "#FF5B6A");
    const threshold = num("LOW_THRESHOLD", 0.25);
    const colour = ratio <= threshold ? low : fill;
    const back = str("BACK_COLOR", "#000000");
    const backT = num("BACK_TRANSPARENCY", 0.55);
    const radius = num("CORNER_RADIUS", 6) * scale;
    const borderW = num("BORDER_THICKNESS", 0) * scale;
    const plain = mode === "Vignette" || mode === "Reticule" || mode === "Points";

    ctx.save();
    ctx.globalAlpha = alpha;

    if (!plain) {
      ctx.fillStyle = withAlpha(back, 1 - backT);
      roundRect(ctx, x, y, w, h, radius);
      ctx.fill();
      if (borderW > 0) {
        ctx.strokeStyle = str("BORDER_COLOR", "#FFFFFF");
        ctx.lineWidth = borderW;
        ctx.stroke();
      }
    }

    const side = Math.min(w, h);
    const cx = x + w / 2, cy = y + h / 2;

    if (mode === "Barre") {
      ctx.fillStyle = colour;
      roundRect(ctx, x, y, Math.max(w * ratio, 0.001), h, radius);
      ctx.fill();

    } else if (mode === "BarreVerticale") {
      ctx.fillStyle = colour;
      roundRect(ctx, x, y + h * (1 - ratio), w, Math.max(h * ratio, 0.001), radius);
      ctx.fill();

    } else if (mode === "BarreCentree") {
      const fw = Math.max(w * ratio, 0.001);
      ctx.fillStyle = colour;
      roundRect(ctx, cx - fw / 2, y, fw, h, radius);
      ctx.fill();

    } else if (mode === "BarreSegments" || mode === "Points") {
      const dots = mode === "Points";
      const n = Math.max(2, Math.round(num("SEGMENT_COUNT", 6)));
      const gap = num("SEGMENT_GAP", 4) * scale;
      const cellW = dots ? h : (w - gap * (n - 1)) / n;
      const total = cellW * n + gap * (n - 1);
      let cxStart = cx - total / 2;
      const exact = ratio * n;
      for (let i = 0; i < n; i++) {
        const part = clamp(exact - i, 0, 1);
        ctx.globalAlpha = alpha * (part >= 1 ? 1 : part <= 0 ? 0.22 : 0.65);
        ctx.fillStyle = colour;
        const cxi = cxStart + i * (cellW + gap);
        roundRect(ctx, cxi, y, cellW, h, dots ? h / 2 : Math.min(radius, 4 * scale));
        ctx.fill();
      }
      ctx.globalAlpha = alpha;

    } else if (mode === "Anneau" || mode === "Arc" || mode === "Reticule") {
      const sweep = mode === "Arc" ? 270 : 360;
      const start = mode === "Arc" ? -135 : 0;
      const n = mode === "Reticule" ? 24 : mode === "Arc" ? 36 : 48;
      const r = side * 0.42;
      const segW = side * 0.085, segH = side * 0.16;
      const lit = ratio * n;
      for (let i = 0; i < n; i++) {
        const deg = start + ((i + 0.5) / n) * sweep;
        const a = (deg * Math.PI) / 180;
        ctx.globalAlpha = alpha * (i < lit ? 1 : 0.2);
        ctx.fillStyle = colour;
        ctx.save();
        ctx.translate(cx + Math.sin(a) * r, cy - Math.cos(a) * r);
        ctx.rotate(a);
        roundRect(ctx, -segW / 2, -segH / 2, segW, segH, 2 * scale);
        ctx.fill();
        ctx.restore();
      }
      ctx.globalAlpha = alpha;

    } else if (mode === "Icone") {
      const s = side * 0.72;
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(Math.PI / 4);
      roundRect(ctx, -s / 2, -s / 2, s, s, Math.max(radius, 3 * scale));
      ctx.save();
      ctx.clip();
      ctx.globalAlpha = alpha * 0.25;
      ctx.fillStyle = colour;
      ctx.fillRect(-s / 2, -s / 2, s, s);
      ctx.globalAlpha = alpha;
      ctx.fillStyle = colour;
      ctx.fillRect(-s / 2, s / 2 - s * ratio, s, s * ratio);
      ctx.restore();
      ctx.restore();

    } else if (mode === "Chiffre") {
      ctx.fillStyle = ratio <= threshold ? low : str("TEXT_COLOR", "#FFFFFF");
      ctx.font = `700 ${Math.round(h * 0.8)}px ui-monospace, Consolas, monospace`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(Math.round(ratio * num("STAMINA_MAX", 100))), cx, cy + h * 0.03);
    }

    // Valeur chiffrée en surimpression, disponible sur toutes les formes.
    if (bool("SHOW_TEXT", false) && mode !== "Chiffre" && mode !== "Vignette") {
      ctx.fillStyle = str("TEXT_COLOR", "#FFFFFF");
      ctx.font = `700 ${Math.round(Math.min(h * 0.72, side * 0.5))}px ui-monospace, Consolas, monospace`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      const max = Math.round(num("STAMINA_MAX", 100));
      ctx.fillText(`${Math.round(ratio * max)} / ${max}`, cx, cy);
    }

    ctx.restore();
  }

  // La vignette ne se pose pas dans un rectangle : elle borde tout l'écran.
  function drawVignette(sx, sy, sw, sh, ratio, alpha) {
    const threshold = num("LOW_THRESHOLD", 0.25);
    const span = Math.max(threshold * 2, 0.01);
    const intensity = clamp((span - ratio) / span, 0, 1) * 0.75 * alpha;
    if (intensity <= 0.004) return;
    const colour = str("FILL_COLOR_LOW", "#FF5B6A");
    const bandY = sh * 0.22, bandX = sw * 0.18;
    const bands = [
      [sx, sy, sw, bandY, 0, 1],
      [sx, sy + sh - bandY, sw, bandY, 0, -1],
      [sx, sy, bandX, sh, 1, 0],
      [sx + sw - bandX, sy, bandX, sh, -1, 0],
    ];
    ctx.save();
    for (const [bx, by, bw, bh, dx, dy] of bands) {
      const g = ctx.createLinearGradient(
        dx > 0 ? bx : dx < 0 ? bx + bw : bx,
        dy > 0 ? by : dy < 0 ? by + bh : by,
        dx > 0 ? bx + bw : dx < 0 ? bx : bx,
        dy > 0 ? by + bh : dy < 0 ? by : by,
      );
      g.addColorStop(0, withAlpha(colour, intensity));
      g.addColorStop(1, withAlpha(colour, 0));
      ctx.fillStyle = g;
      ctx.fillRect(bx, by, bw, bh);
    }
    ctx.restore();
  }

  // ------------------------------------------------------------- la scène
  function drawScene(sx, sy, sw, sh) {
    const sky = ctx.createLinearGradient(0, sy, 0, sy + sh);
    sky.addColorStop(0, "#2c4a72");
    sky.addColorStop(0.62, "#6d93bd");
    sky.addColorStop(0.62, "#4e6b45");
    sky.addColorStop(1, "#33482e");
    ctx.fillStyle = sky;
    ctx.fillRect(sx, sy, sw, sh);

    // quelques blocs au sol pour donner de la profondeur
    ctx.fillStyle = "rgba(0,0,0,.18)";
    for (let i = 0; i < 5; i++) {
      const bw = sw * (0.05 + (i % 3) * 0.02);
      const bx = sx + sw * (0.08 + i * 0.2);
      const bh = sh * (0.08 + (i % 2) * 0.05);
      ctx.fillRect(bx, sy + sh * 0.62 - bh, bw, bh);
    }
  }

  // Personnage R6 stylisé, de face : c'est un repère d'échelle et le support de
  // la jauge « au-dessus du personnage ». Volontairement plat — la maquette
  // porte sur l'interface, pas sur le rendu 3D.
  function drawCharacter(cx, groundY, unit) {
    const headS = unit * 1.2;
    const torsoW = unit * 2, torsoH = unit * 2;
    const armW = unit * 0.7, armH = unit * 2;
    const legW = unit * 0.9, legH = unit * 2;

    const top = groundY - legH - torsoH - headS;
    const shade = (c, k) => {
      const n = parseInt(c.slice(1), 16);
      const r = Math.round(((n >> 16) & 255) * k), g = Math.round(((n >> 8) & 255) * k), b = Math.round((n & 255) * k);
      return `rgb(${clamp(r, 0, 255)},${clamp(g, 0, 255)},${clamp(b, 0, 255)})`;
    };

    ctx.save();
    ctx.fillStyle = "rgba(0,0,0,.25)";
    ctx.beginPath();
    ctx.ellipse(cx, groundY + unit * 0.15, unit * 1.6, unit * 0.35, 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = NOOB.leg;
    ctx.fillRect(cx - legW - unit * 0.05, groundY - legH, legW, legH);
    ctx.fillStyle = shade(NOOB.leg, 0.85);
    ctx.fillRect(cx + unit * 0.05, groundY - legH, legW, legH);

    ctx.fillStyle = NOOB.torso;
    ctx.fillRect(cx - torsoW / 2, groundY - legH - torsoH, torsoW, torsoH);

    ctx.fillStyle = NOOB.arm;
    ctx.fillRect(cx - torsoW / 2 - armW, groundY - legH - torsoH, armW, armH);
    ctx.fillStyle = shade(NOOB.arm, 0.88);
    ctx.fillRect(cx + torsoW / 2, groundY - legH - torsoH, armW, armH);

    ctx.fillStyle = NOOB.head;
    ctx.fillRect(cx - headS / 2, top, headS, headS);
    ctx.fillStyle = "#2b2b2b";
    ctx.fillRect(cx - headS * 0.26, top + headS * 0.35, headS * 0.12, headS * 0.14);
    ctx.fillRect(cx + headS * 0.14, top + headS * 0.35, headS * 0.12, headS * 0.14);
    ctx.restore();

    return top; // sommet de la tête : point d'accroche du billboard
  }

  // ------------------------------------------------------------- rendu
  function draw() {
    ctx.clearRect(0, 0, W, H);

    // l'écran factice, au format choisi, centré dans le canvas
    const pad = 14;
    let sw = W - pad * 2, sh = sw / aspect;
    if (sh > H - pad * 2) { sh = H - pad * 2; sw = sh * aspect; }
    const sx = (W - sw) / 2, sy = (H - sh) / 2;

    ctx.save();
    roundRect(ctx, sx, sy, sw, sh, 10);
    ctx.clip();
    drawScene(sx, sy, sw, sh);

    const max = num("STAMINA_MAX", 100);
    const ratio = max > 0 ? clamp(sim.value / max, 0, 1) : 0;
    const alpha = clamp(sim.shown, 0, 1);
    const mode = str("DISPLAY_MODE", "Barre");
    const target = str("DISPLAY_TARGET", "Ecran");
    const scale = sw / REF_WIDTH;

    // le personnage, un peu à gauche du centre
    const unit = sh * 0.055;
    const groundY = sy + sh * 0.78;
    const charX = sx + sw * 0.32;
    const headTop = drawCharacter(charX, groundY, unit);

    if (mode !== "Aucun") {
      // au-dessus du personnage
      if (target === "Personnage" || target === "Les deux") {
        const wmode = mode === "Vignette" || mode === "Reticule" ? "Barre" : mode;
        const ww = num("WORLD_WIDTH", 4) * STUDS_TO_PX * scale * 2.2;
        const wh = num("WORLD_HEIGHT", 0.45) * STUDS_TO_PX * scale * 2.2;
        const wy = headTop - num("WORLD_OFFSET_Y", 3) * unit * 0.62 - wh / 2;
        drawWidget(wmode, charX - ww / 2, wy, ww, wh, ratio, scale, alpha);
      }

      // à l'écran
      if (target === "Ecran" || target === "Les deux") {
        if (mode === "Vignette") {
          drawVignette(sx, sy, sw, sh, ratio, alpha);
        } else if (mode === "Reticule") {
          const side = Math.max(num("WIDTH", 220), num("HEIGHT", 12)) * scale;
          drawWidget(mode, sx + sw / 2 - side / 2, sy + sh / 2 - side / 2, side, side, ratio, scale, alpha);
          ctx.save();
          ctx.strokeStyle = "rgba(255,255,255,.5)";
          ctx.lineWidth = Math.max(1, scale * 2);
          ctx.beginPath();
          ctx.moveTo(sx + sw / 2 - 5, sy + sh / 2); ctx.lineTo(sx + sw / 2 + 5, sy + sh / 2);
          ctx.moveTo(sx + sw / 2, sy + sh / 2 - 5); ctx.lineTo(sx + sw / 2, sy + sh / 2 + 5);
          ctx.stroke();
          ctx.restore();
        } else {
          const a = ANCHORS[str("SCREEN_ANCHOR", "BasCentre")] || ANCHORS.BasCentre;
          const bw = num("WIDTH", 220) * scale;
          const bh = num("HEIGHT", 12) * scale;
          const bx = sx + sw * a[0] + num("OFFSET_X", 0) * scale - bw * a[0];
          const by = sy + sh * a[1] + num("OFFSET_Y", -14) * scale - bh * a[1];
          drawWidget(mode, bx, by, bw, bh, ratio, scale, alpha);

          // repère d'ancrage : le point auquel la jauge est accrochée
          ctx.save();
          ctx.globalAlpha = 0.55;
          ctx.strokeStyle = "#3fd48a";
          ctx.lineWidth = 1;
          ctx.setLineDash([3, 3]);
          ctx.beginPath();
          ctx.arc(sx + sw * a[0], sy + sh * a[1], 5, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        }
      }
    }
    ctx.restore();

    // cadre de l'écran
    ctx.strokeStyle = "rgba(255,255,255,.14)";
    ctx.lineWidth = 1;
    roundRect(ctx, sx + 0.5, sy + 0.5, sw - 1, sh - 1, 10);
    ctx.stroke();

    // bandeau d'état
    ctx.fillStyle = "rgba(255,255,255,.72)";
    ctx.font = "11px ui-monospace, Consolas, monospace";
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    const lines = [
      `endurance ${Math.round(sim.value)} / ${Math.round(max)}`,
      sim.lockedFor > 0 ? `bloquée ${sim.lockedFor.toFixed(1)} s`
        : sim.draining ? `dépense simulée ${SIM_COST}/s` : "récupération",
    ];
    lines.forEach((t, i) => ctx.fillText(t, sx + 10, sy + 8 + i * 14));
  }

  function frame(now) {
    raf = requestAnimationFrame(frame);
    const dt = last ? Math.min((now - last) / 1000, 0.05) : 0;
    last = now;
    if (playing) step(dt);
    draw();
  }

  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    const r = canvas.getBoundingClientRect();
    W = Math.max(1, Math.round(r.width));
    H = Math.max(1, Math.round(r.height));
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  const ro = new ResizeObserver(resize);
  ro.observe(canvas);
  resize();
  raf = requestAnimationFrame(frame);

  return {
    cameras,
    get camera() { return camId; },
    scenario: api.scenario || "hud",
    setCamera(id) {
      const c = cameras.find((x) => x.id === id);
      if (!c) return;
      camId = id;
      aspect = c.aspect;
    },
    setPlaying(v) { playing = !!v; },
    replay() { reset(); },
    sync() { /* les valeurs sont relues à chaque image */ },
    destroy() {
      cancelAnimationFrame(raf);
      ro.disconnect();
    },
  };
}
