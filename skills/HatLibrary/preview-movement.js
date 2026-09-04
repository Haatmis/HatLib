// preview-movement.js — aperçu animé des prefabs de déplacement.
//
// Chargé à la demande par configurator.html quand le .luau porte l'annotation
// « 🎬 APERÇU: movement/<scenario> ». Sans dépendance : le maillage vient de
// rig-r6.js (export OBJ du rig R6 de Studio) et un projecteur 3D écrit à la main
// suffit à l'afficher — élimination des faces arrière puis tri par profondeur.
//
// Contrat attendu par le configurateur :
//   mount(canvas, { get, scenario }) -> { cameras, camera, setCamera, sync,
//                                         setPlaying, replay, destroy }
// `get(nom, defaut)` lit la valeur courante d'un réglage du bloc CONFIG.

import { RIG } from "./rig-r6.js";

const G = 196.2;              // gravité Roblox par défaut (studs/s²)
const BASE_FOV = 70;          // FieldOfView par défaut de la caméra
const DEFAULT_JUMP_POWER = 50; // Humanoid.JumpPower par défaut

const NOOB = { head: "#F5CD30", torso: "#0D69AC", arm: "#F5CD30", leg: "#2C5E2E" };
const LIGHT = norm([0.45, 1, 0.35]);

// `dist` est calibrée pour que le personnage (5,1 studs) occupe environ le tiers
// de la hauteur du canvas : plus loin, il devient un timbre-poste illisible.
export const cameras = [
  { id: "side", label: "Côté", yaw: 90, pitch: 10, dist: 11 },
  { id: "back", label: "Dos", yaw: 178, pitch: 12, dist: 10 },
  { id: "front", label: "Face", yaw: 2, pitch: 10, dist: 10 },
  { id: "iso", label: "Isométrique", yaw: 132, pitch: 26, dist: 13 },
];

const DEFAULT_CAM = { sprint: "side", dash: "iso", jump: "side" };

// ------------------------------------------------------------------ vecteurs
function norm(v) {
  const l = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / l, v[1] / l, v[2] / l];
}
function cross(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const approach = (cur, target, tau, dt) =>
  tau <= 0.001 ? target : cur + (target - cur) * clamp(dt / tau, 0, 1);

// ------------------------------------------------------------------ caméra
// Vue sphérique autour d'une cible qui suit le personnage. La position de l'œil
// est cible + dist * direction(yaw, pitch) ; on regarde toujours la cible.
function makeView(cam, w, h, fovDeg) {
  const ya = (cam.yaw * Math.PI) / 180, pa = (cam.pitch * Math.PI) / 180;
  const dir = [Math.cos(ya) * Math.cos(pa), Math.sin(pa), Math.sin(ya) * Math.cos(pa)];
  const eye = [
    cam.target[0] + dir[0] * cam.dist,
    cam.target[1] + dir[1] * cam.dist,
    cam.target[2] + dir[2] * cam.dist,
  ];
  const fwd = norm([cam.target[0] - eye[0], cam.target[1] - eye[1], cam.target[2] - eye[2]]);
  const right = norm(cross(fwd, [0, 1, 0]));
  const up = cross(right, fwd);
  const f = (h / 2) / Math.tan((fovDeg * Math.PI) / 360);
  return {
    w, h, eye, f,
    // monde -> caméra : x droite, y haut, z profondeur (positive devant)
    to(p) {
      const d = [p[0] - eye[0], p[1] - eye[1], p[2] - eye[2]];
      return [dot(d, right), dot(d, up), dot(d, fwd)];
    },
    // caméra -> écran ; z <= 0 = derrière l'œil, non projetable
    px(c) {
      return [w / 2 + (c[0] * f) / c[2], h / 2 - (c[1] * f) / c[2]];
    },
  };
}

// ------------------------------------------------------------------ couleurs
function shade(hex, k) {
  const n = parseInt(hex.slice(1), 16);
  const r = Math.round(((n >> 16) & 255) * k), g = Math.round(((n >> 8) & 255) * k), b = Math.round((n & 255) * k);
  return `rgb(${clamp(r, 0, 255)},${clamp(g, 0, 255)},${clamp(b, 0, 255)})`;
}

// ------------------------------------------------------------------ le rig
// Vrai maillage : rig-r6.js est l'export OBJ du rig R6 de Studio, converti en
// sommets + triangles (pieds à y = 0, corps centré, regard vers +X). Les quatre
// membres pivotent autour de l'axe Z ; torse et tête sont rigides.
// `sw` et `tk` sont les coefficients de balancement et de repli du membre.
const PARTS = [
  { key: "legL", color: NOOB.leg, sw: 1, tk: 1 },
  { key: "legR", color: NOOB.leg, sw: -1, tk: 1 },
  { key: "torso", color: NOOB.torso },
  { key: "armL", color: NOOB.arm, sw: -1, tk: -0.6 },
  { key: "armR", color: NOOB.arm, sw: 1, tk: -0.6 },
  { key: "head", color: NOOB.head },
];

// Préparation faite une fois : pivot du membre (le haut de sa boîte, au milieu
// de sa largeur), normale de chaque triangle, et tampons réutilisés à chaque
// image pour ne rien allouer dans la boucle de rendu.
for (const spec of PARTS) {
  const part = RIG[spec.key];
  const v = part.v, t = part.t, tris = t.length / 3;
  const nrm = new Float32Array(tris * 3);
  for (let i = 0; i < tris; i++) {
    const a = t[i * 3] * 3, b = t[i * 3 + 1] * 3, c = t[i * 3 + 2] * 3;
    const ux = v[b] - v[a], uy = v[b + 1] - v[a + 1], uz = v[b + 2] - v[a + 2];
    const wx = v[c] - v[a], wy = v[c + 1] - v[a + 1], wz = v[c + 2] - v[a + 2];
    const nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
    const l = Math.hypot(nx, ny, nz) || 1;
    nrm[i * 3] = nx / l; nrm[i * 3 + 1] = ny / l; nrm[i * 3 + 2] = nz / l;
  }
  spec.part = part;
  spec.norm = nrm;
  spec.pivot = [0, part.box[1][1], (part.box[2][0] + part.box[2][1]) / 2];
  spec.wld = new Float64Array(v.length);           // sommets en repère monde
  spec.cam = new Float64Array(v.length);           // ... et en repère caméra
  spec.scr = new Float64Array((v.length / 3) * 2); // ... et à l'écran
}

// Remplit `out` avec les triangles visibles du personnage, prêts à être triés.
function collectRig(view, out, sim) {
  const eye = view.eye;
  for (const spec of PARTS) {
    const { part, norm, wld, cam, scr, pivot } = spec;
    const v = part.v, t = part.t;
    const ang = spec.sw ? spec.sw * sim.swing + spec.tk * sim.tuck : 0;
    const ca = Math.cos(ang), sa = Math.sin(ang);
    const pvx = pivot[0], pvy = pivot[1];

    for (let i = 0, n = v.length / 3; i < n; i++) {
      let x = v[i * 3], y = v[i * 3 + 1];
      if (ang) {
        const dx = x - pvx, dy = y - pvy;
        x = pvx + dx * ca - dy * sa;
        y = pvy + dx * sa + dy * ca;
      }
      x += sim.x; y += sim.y;
      const z = v[i * 3 + 2] + sim.z;
      wld[i * 3] = x; wld[i * 3 + 1] = y; wld[i * 3 + 2] = z;
      const c = view.to([x, y, z]);
      cam[i * 3] = c[0]; cam[i * 3 + 1] = c[1]; cam[i * 3 + 2] = c[2];
      if (c[2] > 0.2) {
        const p = view.px(c);
        scr[i * 2] = p[0]; scr[i * 2 + 1] = p[1];
      }
    }

    for (let i = 0, m = t.length / 3; i < m; i++) {
      const ia = t[i * 3], ib = t[i * 3 + 1], ic = t[i * 3 + 2];
      const za = cam[ia * 3 + 2], zb = cam[ib * 3 + 2], zc = cam[ic * 3 + 2];
      if (za <= 0.2 || zb <= 0.2 || zc <= 0.2) continue;

      // Normale du triangle, tournée comme le membre auquel il appartient.
      let nx = norm[i * 3], ny = norm[i * 3 + 1];
      const nz = norm[i * 3 + 2];
      if (ang) { const rx = nx * ca - ny * sa; ny = nx * sa + ny * ca; nx = rx; }

      // Face détournée de l'œil : inutile de la dessiner, elle est de toute
      // façon cachée par la face opposée du même volume.
      const dx = wld[ia * 3] - eye[0], dy = wld[ia * 3 + 1] - eye[1], dz = wld[ia * 3 + 2] - eye[2];
      if (nx * dx + ny * dy + nz * dz > 0) continue;

      const k = 0.42 + 0.58 * Math.max(0, nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]);
      out.push({
        z: (za + zb + zc) / 3,
        fill: shade(spec.color, k),
        p: [scr[ia * 2], scr[ia * 2 + 1], scr[ib * 2], scr[ib * 2 + 1], scr[ic * 2], scr[ic * 2 + 1]],
      });
    }
  }
}

// ------------------------------------------------------------------ montage
export function mount(canvas, api) {
  const ctx = canvas.getContext("2d");
  const scenario = ["sprint", "dash", "jump"].includes(api.scenario) ? api.scenario : "sprint";
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

  const preset = cameras.find((c) => c.id === DEFAULT_CAM[scenario]) || cameras[0];
  const cam = { yaw: preset.yaw, pitch: preset.pitch, dist: preset.dist, target: [0, 3, 0] };
  let camId = preset.id;

  let playing = true, raf = 0, last = 0, dpr = 1, W = 0, H = 0;
  let sim = null;
  const hud = [];       // lignes de texte redessinées à chaque image
  const tris = [];      // tampon de triangles du rig, vidé à chaque image
  let flash = "";       // libellé transitoire (ex. « ruée ! »)

  // ------------------------------------------------------------ simulation
  function reset() {
    sim = {
      t: 0, x: 0, y: 0, z: 0, vy: 0, speed: 0, swing: 0, tuck: 0, phase: 0, fov: BASE_FOV,
      trail: [], puffs: [], onGround: true, jumps: 0, nextJump: 0,
      stamina: num("STAMINA_MAX", 100), sinceDrain: 99, sprinting: false,
      dashing: false, dashLeft: 0, cooldown: 0, dashFrom: 0, dashSpan: 0,
      peak: 0, mark: 0,
    };
    flash = "";
  }
  reset();

  function stepSprint(dt) {
    const walk = num("WALK_SPEED", 16), run = num("SPRINT_SPEED", 24);
    const tween = num("SPEED_TWEEN_TIME", 0.25);
    const useStam = bool("ENABLE_STAMINA", false);
    const drain = num("STAMINA_DRAIN", 20), regen = num("STAMINA_REGEN", 15);
    const max = num("STAMINA_MAX", 100), minStart = num("STAMINA_MIN_TO_START", 5);
    const delay = num("STAMINA_REGEN_DELAY", 1);

    // L'utilisateur « tient la touche » en continu à partir d'une seconde : ce
    // qu'on regarde, c'est jusqu'où l'endurance le laisse aller.
    const wants = sim.t > 1;
    if (useStam) {
      if (sim.sprinting && sim.stamina <= 0) sim.sprinting = false;
      else if (wants && !sim.sprinting && sim.stamina >= minStart) sim.sprinting = true;
      else if (!wants) sim.sprinting = false;
      if (sim.sprinting) {
        sim.stamina = Math.max(0, sim.stamina - drain * dt);
        sim.sinceDrain = 0;
      } else {
        sim.sinceDrain += dt;
        if (sim.sinceDrain >= delay) sim.stamina = Math.min(max, sim.stamina + regen * dt);
      }
    } else {
      sim.sprinting = wants;
    }

    sim.speed = approach(sim.speed, sim.sprinting ? run : walk, tween, dt);
    const boost = bool("ENABLE_FOV", true) ? num("FOV_BOOST", 12) : 0;
    sim.fov = approach(sim.fov, BASE_FOV + (sim.sprinting ? boost : 0), num("FOV_TWEEN_TIME", 0.3), dt);

    hud.push(["vitesse", sim.speed.toFixed(1) + " studs/s"]);
    hud.push(["mode", sim.sprinting ? "sprint" : "marche"]);
    if (useStam) {
      hud.push(["endurance", Math.round(sim.stamina) + " / " + Math.round(max)]);
      const net = drain - regen;
      if (drain > 0) hud.push(["sprint tenable", (max / drain).toFixed(1) + " s"]);
      if (net <= 0) flash = "regen ≥ drain : sprint infini";
    }
  }

  function stepDash(dt) {
    const speed = num("DASH_SPEED", 80), dur = num("DASH_DURATION", 0.2);
    const cd = num("DASH_COOLDOWN", 1.5), cruise = 16;

    if (sim.dashing) {
      sim.dashLeft -= dt;
      sim.speed = speed;
      if (sim.dashLeft <= 0) {
        sim.dashing = false;
        sim.cooldown = cd;
        sim.dashSpan = sim.x - sim.dashFrom;
      }
    } else {
      sim.cooldown = Math.max(0, sim.cooldown - dt);
      sim.speed = approach(sim.speed, cruise, 0.2, dt);
      // Relance dès que la recharge est finie, avec un temps mort lisible.
      if (sim.cooldown === 0 && sim.t > 0.8) {
        sim.dashing = true;
        sim.dashLeft = dur;
        sim.dashFrom = sim.x;
        sim.cooldown = cd + dur;
        flash = "ruée !";
      }
    }

    const boost = bool("ENABLE_FOV", true) ? num("FOV_BOOST", 15) : 0;
    sim.fov = approach(sim.fov, BASE_FOV + (sim.dashing ? boost : 0), num("FOV_TWEEN_TIME", 0.15), dt);

    if (bool("ENABLE_TRAIL", true)) {
      if (sim.dashing) sim.trail.push({ p: [sim.x, sim.y + 3, 0], t: sim.t });
      const life = num("TRAIL_LIFETIME", 0.35);
      sim.trail = sim.trail.filter((s) => sim.t - s.t < life);
    } else sim.trail.length = 0;

    hud.push(["vitesse", sim.speed.toFixed(0) + " studs/s"]);
    hud.push(["portée", (speed * dur).toFixed(1) + " studs"]);
    hud.push(["recharge", sim.dashing ? "—" : sim.cooldown.toFixed(2) + " s"]);
    hud.push(["cadence", (1 / (dur + cd)).toFixed(2) + " ruée/s"]);
  }

  function stepJump(dt) {
    const maxJumps = Math.max(1, Math.round(num("MAX_JUMPS", 2)));
    const power = num("EXTRA_JUMP_POWER", 50);
    const resetFall = bool("RESET_FALL_SPEED", true);
    const gap = Math.max(num("INPUT_COOLDOWN", 0.15), 0.3);

    sim.speed = 16;
    sim.vy -= G * dt;
    sim.y = Math.max(0, sim.y + sim.vy * dt);
    sim.onGround = sim.y <= 0.0001;
    if (sim.onGround) {
      sim.vy = 0;
      if (sim.t > 0.6 && sim.jumps === 0) {
        sim.vy = DEFAULT_JUMP_POWER;
        sim.jumps = 1;
        sim.nextJump = sim.t + gap;
        sim.peak = 0;
      }
    } else if (sim.jumps > 0 && sim.jumps < maxJumps && sim.t >= sim.nextJump) {
      // Sans remise à zéro de la chute, la vitesse descendante mange le saut :
      // c'est exactement ce que RESET_FALL_SPEED corrige.
      sim.vy = resetFall ? power : Math.min(power, power + sim.vy);
      sim.jumps++;
      sim.nextJump = sim.t + gap;
      if (bool("ENABLE_PUFF", true)) sim.puffs.push({ p: [sim.x, sim.y, 0], t: sim.t });
      flash = "saut " + sim.jumps;
    }
    sim.peak = Math.max(sim.peak, sim.y);
    if (sim.onGround && sim.jumps >= maxJumps) { sim.jumps = 0; sim.mark = sim.peak; }

    sim.puffs = sim.puffs.filter((p) => sim.t - p.t < 0.45);

    hud.push(["sauts", sim.jumps + " / " + maxJumps]);
    hud.push(["hauteur", sim.y.toFixed(1) + " studs"]);
    hud.push(["apogée", ((sim.mark || sim.peak) || 0).toFixed(1) + " studs"]);
    const h = (power * power) / (2 * G);
    hud.push(["saut en l'air", "≈ " + h.toFixed(1) + " studs de gain"]);
  }

  function step(dt) {
    hud.length = 0;
    sim.t += dt;
    if (scenario === "sprint") stepSprint(dt);
    else if (scenario === "dash") stepDash(dt);
    else stepJump(dt);

    sim.x += sim.speed * dt;
    // Cadence des membres proportionnelle à la vitesse ; en l'air, jambes repliées.
    sim.phase += sim.speed * dt * 0.55;
    sim.swing = sim.onGround ? Math.sin(sim.phase) * clamp(sim.speed / 40, 0.1, 0.9) : Math.sin(sim.phase) * 0.15;
    // En l'air, jambes repliées et bras relevés — le repli s'installe en douceur.
    sim.tuck = approach(sim.tuck, sim.onGround ? 0 : 0.5, 0.12, dt);

    // La caméra suit sans coller : la cible glisse vers le personnage. Le retard
    // est borné, sinon une ruée à 80 studs/s passe derrière l'œil et un saut
    // sort du cadre par le haut — le retard toléré est plus court en hauteur.
    const want = [sim.x, sim.y + 3, 0];
    const maxLag = [3, 1.5, 3];
    for (let i = 0; i < 3; i++) {
      const v = approach(cam.target[i], want[i], 0.09, dt);
      cam.target[i] = clamp(v, want[i] - maxLag[i], want[i] + maxLag[i]);
    }
  }

  // ---------------------------------------------------------------- rendu
  function draw() {
    const view = makeView(cam, W, H, sim.fov);
    ctx.clearRect(0, 0, W, H);

    // ciel
    const sky = ctx.createLinearGradient(0, 0, 0, H);
    sky.addColorStop(0, "#0d1119");
    sky.addColorStop(1, "#1b2230");
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, W, H);

    drawGround(view);
    drawPuffs(view);

    // Peintre : les triangles les plus lointains d'abord. Le léger contour de
    // la même couleur ferme les coutures d'antialiasing entre triangles voisins.
    tris.length = 0;
    collectRig(view, tris, sim);
    tris.sort((a, b) => b.z - a.z);
    for (const t of tris) {
      const p = t.p;
      ctx.beginPath();
      ctx.moveTo(p[0], p[1]);
      ctx.lineTo(p[2], p[3]);
      ctx.lineTo(p[4], p[5]);
      ctx.closePath();
      ctx.fillStyle = ctx.strokeStyle = t.fill;
      ctx.lineWidth = 1;
      ctx.fill();
      ctx.stroke();
    }

    drawTrail(view);
    drawHud();
  }

  function seg(view, a, b, style, width) {
    const ca = view.to(a), cb = view.to(b);
    if (ca[2] <= 0.2 || cb[2] <= 0.2) return;
    const pa = view.px(ca), pb = view.px(cb);
    ctx.strokeStyle = style;
    ctx.lineWidth = width || 1;
    ctx.beginPath();
    ctx.moveTo(pa[0], pa[1]);
    ctx.lineTo(pb[0], pb[1]);
    ctx.stroke();
  }

  function drawGround(view) {
    const cx = Math.round(sim.x / 4) * 4;
    const span = 40;
    ctx.save();
    for (let x = cx - span; x <= cx + span; x += 4) {
      const major = Math.abs(x % 20) < 0.001;
      seg(view, [x, 0, -span / 2], [x, 0, span / 2], major ? "#3b4356" : "#2a3040", 1);
    }
    ctx.restore();
    // ligne de fuite + repères chiffrés tous les 20 studs
    for (let z = -16; z <= 16; z += 4) seg(view, [cx - span, 0, z], [cx + span, 0, z], "#232935", 1);
    ctx.fillStyle = "#6c7488";
    ctx.font = "11px ui-monospace, Consolas, monospace";
    for (let x = cx - 60; x <= cx + 60; x += 20) {
      const c = view.to([x, 0.05, -12]);
      if (c[2] <= 0.2) continue;
      const p = view.px(c);
      ctx.fillText(x + " studs", p[0] + 3, p[1] - 3);
    }
    // ombre portée
    const c = view.to([sim.x, 0.02, 0]);
    if (c[2] > 0.2) {
      const p = view.px(c);
      const r = (view.f / c[2]) * 1.6;
      ctx.fillStyle = "rgba(0,0,0," + clamp(0.45 - sim.y * 0.02, 0.08, 0.45) + ")";
      ctx.beginPath();
      ctx.ellipse(p[0], p[1], r, r * 0.45, 0, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function drawTrail(view) {
    if (sim.trail.length < 2) return;
    const life = num("TRAIL_LIFETIME", 0.35);
    const col = String(get("TRAIL_COLOR", "#7FD4FF"));
    const w = num("TRAIL_WIDTH", 2);
    for (let i = 1; i < sim.trail.length; i++) {
      const age = (sim.t - sim.trail[i].t) / (life || 1);
      const a = clamp(1 - age, 0, 1) * 0.8;
      const ca = view.to(sim.trail[i - 1].p), cb = view.to(sim.trail[i].p);
      if (ca[2] <= 0.2 || cb[2] <= 0.2) continue;
      const pa = view.px(ca), pb = view.px(cb);
      ctx.strokeStyle = hexA(col, a);
      ctx.lineWidth = Math.max(1, (view.f / cb[2]) * w * 0.5);
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(pa[0], pa[1]);
      ctx.lineTo(pb[0], pb[1]);
      ctx.stroke();
    }
  }

  function drawPuffs(view) {
    const col = String(get("PUFF_COLOR", "#FFFFFF"));
    const size = num("PUFF_SIZE", 4);
    for (const puff of sim.puffs) {
      const k = (sim.t - puff.t) / 0.45;
      const c = view.to(puff.p);
      if (c[2] <= 0.2) continue;
      const p = view.px(c);
      const r = ((view.f / c[2]) * size * k) / 2;
      ctx.strokeStyle = hexA(col, clamp(1 - k, 0, 1) * 0.8);
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.ellipse(p[0], p[1], r, r * 0.4, 0, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  function hexA(hex, a) {
    const s = /^#[0-9a-fA-F]{6}$/.test(hex) ? hex : "#FFFFFF";
    const n = parseInt(s.slice(1), 16);
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a.toFixed(3)})`;
  }

  function drawHud() {
    ctx.font = "12px ui-monospace, Consolas, monospace";
    let y = 18;
    for (const row of hud) {
      if (!row) continue;
      ctx.fillStyle = "#7f889c";
      ctx.fillText(row[0], 12, y);
      ctx.fillStyle = "#e6e8ec";
      ctx.fillText(String(row[1]), 108, y);
      y += 16;
    }
    if (flash) {
      ctx.fillStyle = "#5b8cff";
      ctx.font = "600 13px ui-monospace, Consolas, monospace";
      ctx.fillText(flash, 12, y + 4);
    }
    // jauge d'endurance, quand le prefab en a une
    if (scenario === "sprint" && bool("ENABLE_STAMINA", false) && bool("ENABLE_STAMINA_BAR", true)) {
      const max = num("STAMINA_MAX", 100) || 1;
      const w = 120, x = W - w - 14, by = H - 22;
      ctx.fillStyle = "rgba(0,0,0,.45)";
      ctx.fillRect(x, by, w, 8);
      ctx.fillStyle = String(get("STAMINA_BAR_COLOR", "#5B8CFF"));
      ctx.fillRect(x, by, (w * clamp(sim.stamina / max, 0, 1)), 8);
    }
    // recharge de la ruée
    if (scenario === "dash") {
      const cd = num("DASH_COOLDOWN", 1.5) + num("DASH_DURATION", 0.2);
      const w = 120, x = W - w - 14, by = H - 22;
      ctx.fillStyle = "rgba(0,0,0,.45)";
      ctx.fillRect(x, by, w, 8);
      ctx.fillStyle = sim.cooldown > 0 ? "#8a90a0" : "#3fd48a";
      ctx.fillRect(x, by, w * clamp(1 - sim.cooldown / (cd || 1), 0, 1), 8);
    }
  }

  // ---------------------------------------------------------------- boucle
  function frame(now) {
    raf = requestAnimationFrame(frame);
    const dt = Math.min(0.05, (now - last) / 1000 || 0);
    last = now;
    if (playing) step(dt);
    draw();
  }

  function resize() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = canvas.clientWidth;
    H = canvas.clientHeight;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  // ------------------------------------------------------------- souris
  let dragging = false, lastX = 0, lastY = 0;
  const onDown = (e) => { dragging = true; lastX = e.clientX; lastY = e.clientY; canvas.setPointerCapture(e.pointerId); };
  const onMove = (e) => {
    if (!dragging) return;
    cam.yaw += (e.clientX - lastX) * 0.4;
    cam.pitch = clamp(cam.pitch - (e.clientY - lastY) * 0.3, -5, 75);
    lastX = e.clientX; lastY = e.clientY;
    camId = "";
    api.onCamera && api.onCamera("");
  };
  const onUp = () => { dragging = false; };
  const onWheel = (e) => { e.preventDefault(); cam.dist = clamp(cam.dist * (1 + e.deltaY * 0.0012), 8, 90); };
  canvas.addEventListener("pointerdown", onDown);
  canvas.addEventListener("pointermove", onMove);
  canvas.addEventListener("pointerup", onUp);
  canvas.addEventListener("pointercancel", onUp);
  canvas.addEventListener("wheel", onWheel, { passive: false });
  const ro = new ResizeObserver(resize);
  ro.observe(canvas);

  resize();
  raf = requestAnimationFrame(frame);

  return {
    cameras,
    get camera() { return camId; },
    scenario,
    setCamera(id) {
      const c = cameras.find((x) => x.id === id);
      if (!c) return;
      camId = id;
      cam.yaw = c.yaw; cam.pitch = c.pitch; cam.dist = c.dist;
    },
    setPlaying(v) { playing = !!v; },
    replay() { reset(); },
    sync() { /* les valeurs sont relues à chaque image : rien à faire */ },
    destroy() {
      cancelAnimationFrame(raf);
      ro.disconnect();
      canvas.removeEventListener("pointerdown", onDown);
      canvas.removeEventListener("pointermove", onMove);
      canvas.removeEventListener("pointerup", onUp);
      canvas.removeEventListener("pointercancel", onUp);
      canvas.removeEventListener("wheel", onWheel);
    },
  };
}
