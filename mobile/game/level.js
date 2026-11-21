// A level as exported from Godot by shopping-cart/tools/mobile_level_export.gd: <key>.glb (what you see) and
// <key>.json (what you touch, how it's lit, where the carts are). Builds the Rapier world and the three.js scene.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { v3, xfMatrix, xfPose, color, godotGroups, widenMask } from './util.js';
import { shapeDesc, massProps } from './cart.js';

const PROJECT_LINEAR_DAMP = 0.02, PROJECT_ANGULAR_DAMP = 0.05;
const CELL = 24;   // m: static meshes are merged per material within cells this size, so far-off ones still cull
const TONEMAPS = [THREE.LinearToneMapping, THREE.ReinhardToneMapping, THREE.CineonToneMapping, THREE.ACESFilmicToneMapping, THREE.AgXToneMapping];

export async function fetchLevel(base, key) {
  const [json, gltf] = await Promise.all([
    fetch(`${base}/${key}.json`).then(r => { if (!r.ok) throw new Error(`${key}.json: ${r.status}`); return r.json(); }),
    new GLTFLoader().loadAsync(`${base}/${key}.glb`),
  ]);
  return { json, gltf };
}

/** Every Godot [layer, mask] pair in the level and the cart rig, to widen masks (see util.js). */
export function layerPairs(json, rig) {
  const pairs = [[1, 0xffff]];
  for (const b of json.bodies) pairs.push([b.layer, b.mask]);
  for (const b of [...rig.bodies, ...rig.groceries]) pairs.push([b.layer, b.mask]);
  return pairs;
}

/**
 * Builds the level into `world` and `root` (a THREE.Group). Returns {props, labels, lights, spawn, spareCarts, ...}.
 */
export function buildLevel(ctx, { json, gltf }, root, opts = {}) {
  const { RAPIER, world } = ctx;
  const MIN = RAPIER.CoefficientCombineRule.Min;

  // ---------------------------------------------------------------- physics: statics in one fixed body
  const fixed = world.createRigidBody(RAPIER.RigidBodyDesc.fixed());
  const surfaces = new Map();   // collider handle -> floor material name (asphalt, tile, ...): picks the rolling sound
  for (const s of json.statics) {
    const d = shapeDesc(RAPIER, s);
    if (!d) continue;
    const c = world.createCollider(d.setFriction(s.friction).setFrictionCombineRule(MIN).setCollisionGroups(godotGroups(1, 0xffff)), fixed);
    if (s.surface) surfaces.set(c.handle, s.surface);
  }

  // ---------------------------------------------------------------- what you see
  const scene = gltf.scene;
  scene.updateMatrixWorld(true);
  const props = [];
  for (const b of json.bodies) {
    const { p, q } = xfPose(xfMatrix(b.xf));
    const { com, inertia } = massProps(b.mass, b.shapes, b.com);
    const body = world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(p.x, p.y, p.z).setRotation(q)
      .setAdditionalMassProperties(b.mass, com, inertia, { x: 0, y: 0, z: 0, w: 1 }).setCanSleep(b.can_sleep)
      .setLinearDamping(PROJECT_LINEAR_DAMP).setAngularDamping(PROJECT_ANGULAR_DAMP));
    const g = godotGroups(b.layer, ctx.widen(b.layer, b.mask));
    for (const s of b.shapes) {
      const d = shapeDesc(RAPIER, s);
      if (d) world.createCollider(d.setDensity(0).setFriction(b.friction).setFrictionCombineRule(MIN).setCollisionGroups(g), body);
    }
    body.sleep();   // loose props start at rest, as in Godot, until something touches them
    const node = scene.getObjectByName(b.node);
    if (node) { root.attach(node); node.traverse(o => { if (o.isMesh) { o.castShadow = o.receiveShadow = true; } }); }
    props.push({ body, node });
  }
  // Endless grids (the sandbox lot): one block came over; repeat it at every grid position.
  const tiles = new EndlessTiles(ctx, scene, root, json.tiles || [], surfaces, opts);
  // Everything else never moves: merge it per material (and per cell), so the phone draws a few hundred meshes
  // instead of thousands.
  const buckets = new Map();
  scene.traverse(o => {
    if (!o.isMesh || !o.geometry) return;
    const g = o.geometry, attrs = Object.keys(g.attributes).sort().join(','), mats = Array.isArray(o.material) ? o.material : [o.material];
    const c = new THREE.Box3().setFromObject(o).getCenter(new THREE.Vector3());
    const cell = `${Math.floor(c.x / CELL)},${Math.floor(c.y / CELL)},${Math.floor(c.z / CELL)}`;
    // glTF meshes have one material per primitive, and three.js makes each primitive its own mesh.
    const geo = g.clone().applyMatrix4(o.matrixWorld);
    const key = `${mats[0].uuid}|${attrs}|${g.index ? 'i' : 'n'}|${cell}`;
    if (!buckets.has(key)) buckets.set(key, { mat: mats[0], geos: [] });
    buckets.get(key).geos.push(geo);
  });
  let drawn = tiles.drawn, tris = tiles.tris;
  for (const { mat, geos } of buckets.values()) {
    const merged = geos.length === 1 ? geos[0] : mergeGeometries(geos, false);
    for (const g of geos) if (g !== merged) g.dispose();
    if (!merged) continue;
    merged.computeBoundingSphere();
    const m = new THREE.Mesh(merged, mat);
    m.castShadow = !(mat.transparent) && !opts.noShadows; m.receiveShadow = true;
    if (mat.map) mat.map.anisotropy = 4;
    root.add(m); drawn++; tris += merged.attributes.position.count / 3;
  }
  scene.traverse(o => { if (o.isMesh) o.geometry.dispose(); });

  // ---------------------------------------------------------------- labels (Label3D)
  const labelCache = new Map();
  for (const l of json.labels) {
    const key = JSON.stringify([l.text, l.font_size, l.color, l.outline_color, l.outline_size, l.double_sided, l.h_align]);
    let tex = labelCache.get(key);
    if (!tex) { tex = labelTexture(l); labelCache.set(key, tex); }
    const w = tex.userData.w * l.pixel_size, h = tex.userData.h * l.pixel_size;
    let obj;
    if (l.billboard) {
      obj = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, alphaTest: 0.05, depthWrite: false }));
      obj.scale.set(w, h, 1);
      obj.position.copy(new THREE.Vector3().setFromMatrixPosition(xfMatrix(l.xf)));
    } else {
      obj = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: tex, transparent: true, alphaTest: 0.05,
        depthWrite: false, side: l.double_sided ? THREE.DoubleSide : THREE.FrontSide, polygonOffset: true, polygonOffsetFactor: -2 }));
      obj.applyMatrix4(xfMatrix(l.xf));
    }
    obj.renderOrder = 1;
    root.add(obj);
  }

  // ---------------------------------------------------------------- light
  const env = json.environment || {};
  const lights = new LightPool(root, json.lights, opts.lightCount);
  return { props, lights, tiles, drawn, tris, env, sun: json.sun, spawn: json.spawn, spareCarts: json.spare_carts,
    botCarts: json.bot_carts || [], navmesh: json.navmesh, name: json.name, surfaces };
}

/**
 * An endless grid as the Godot game's EndlessTiles (scripts/levels/endless_tiles.gd) builds it: one block (the
 * .glb node `tiles_<n>`, its shapes in the JSON in block coordinates) copied to every grid position. update()
 * moves a copy that falls more than half a span behind the camera a whole span ahead, meshes and colliders.
 */
class EndlessTiles {
  constructor(ctx, scene, root, list, surfaces, opts) {
    const { RAPIER, world } = ctx;
    const MIN = RAPIER.CoefficientCombineRule.Min;
    this.grids = []; this.drawn = 0; this.tris = 0;
    for (const t of list) {
      const node = scene.getObjectByName(t.node);
      if (!node) continue;
      node.removeFromParent();
      // The block's meshes, merged per material, in the block's own coordinates.
      const toBlock = node.matrixWorld.clone().invert(), buckets = new Map();
      node.traverse(o => {
        if (!o.isMesh || !o.geometry) return;
        const mat = Array.isArray(o.material) ? o.material[0] : o.material;
        const geo = o.geometry.clone().applyMatrix4(toBlock.clone().multiply(o.matrixWorld));
        const key = `${mat.uuid}|${Object.keys(geo.attributes).sort().join(',')}|${geo.index ? 'i' : 'n'}`;
        if (!buckets.has(key)) buckets.set(key, { mat, geos: [] });
        buckets.get(key).geos.push(geo);
      });
      const block = new THREE.Group();
      for (const { mat, geos } of buckets.values()) {
        const merged = geos.length === 1 ? geos[0] : mergeGeometries(geos, false);
        if (!merged) continue;
        merged.computeBoundingSphere();
        const m = new THREE.Mesh(merged, mat);
        m.castShadow = !(mat.transparent) && !opts.noShadows; m.receiveShadow = true;
        if (mat.map) mat.map.anisotropy = 4;
        block.add(m);
        this.tris += merged.attributes.position.count / 3 * t.origins.length;
      }
      node.traverse(o => { if (o.isMesh) o.geometry.dispose(); });
      const copies = t.origins.map(o => {
        const group = block.clone();
        group.position.set(o[0], o[1], o[2]);
        root.add(group);
        const body = world.createRigidBody(RAPIER.RigidBodyDesc.fixed().setTranslation(o[0], o[1], o[2]));
        for (const s of t.statics) {
          const d = shapeDesc(RAPIER, s);
          if (!d) continue;
          const c = world.createCollider(d.setFriction(s.friction).setFrictionCombineRule(MIN).setCollisionGroups(godotGroups(1, 0xffff)), body);
          if (s.surface) surfaces.set(c.handle, s.surface);
        }
        return { group, body, p: new THREE.Vector3(o[0], o[1], o[2]) };
      });
      this.drawn += block.children.length * copies.length;
      this.grids.push({ span: t.span, copies });
    }
  }
  update(focus) {
    for (const { span, copies } of this.grids) {
      for (const c of copies) {
        const dx = Math.round((focus.x - c.p.x) / span[0]) * span[0], dz = Math.round((focus.z - c.p.z) / span[1]) * span[1];
        if (!dx && !dz) continue;
        c.p.x += dx; c.p.z += dz;
        c.group.position.copy(c.p);
        c.body.setTranslation({ x: c.p.x, y: c.p.y, z: c.p.z }, true);
      }
    }
  }
}

/** Draws a Label3D's text the way Godot does: font_size px per line, pixel_size m per px, centred. */
function labelTexture(l) {
  const S = 2;   // drawn at twice the size so it stays sharp up close
  const lines = String(l.text).split('\n');
  const font = `600 ${l.font_size * S}px "Barlow Condensed", "Arial Narrow", Arial, sans-serif`;
  const c = document.createElement('canvas'), x = c.getContext('2d');
  x.font = font;
  const pad = (l.outline_size || 0) * S + 4;
  const lineH = l.font_size * S * 1.2 + (l.line_spacing || 0) * S;
  const w = Math.ceil(Math.max(...lines.map(t => x.measureText(t).width)) + pad * 2), h = Math.ceil(lineH * lines.length + pad * 2);
  c.width = w; c.height = h;
  x.font = font; x.textBaseline = 'middle';
  x.textAlign = ['left', 'center', 'right', 'center'][l.h_align] || 'center';
  const ax = x.textAlign === 'left' ? pad : x.textAlign === 'right' ? w - pad : w / 2;
  const css = c4 => `rgba(${Math.round(c4[0] * 255)},${Math.round(c4[1] * 255)},${Math.round(c4[2] * 255)},${c4[3]})`;
  lines.forEach((t, i) => {
    const y = pad + lineH * (i + 0.5);
    if (l.outline_size > 0) { x.lineWidth = l.outline_size * S; x.strokeStyle = css(l.outline_color); x.lineJoin = 'round'; x.strokeText(t, ax, y); }
    x.fillStyle = css(l.color); x.fillText(t, ax, y);
  });
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 4;
  tex.userData = { w: w / S, h: h / S };
  return tex;
}

/**
 * Godot levels have dozens of lamps; a phone can't shade that many lights per pixel. A fixed handful of lights
 * (so the shaders never recompile) moves to the lamps nearest the camera's target. Godot multiplies light energy
 * by pi; three.js doesn't, so intensities are energy * pi.
 */
class LightPool {
  constructor(root, lamps, count = { omni: 4, spot: 3 }) {
    this.lamps = lamps.map(l => ({ ...l, p: new THREE.Vector3(...l.pos) }));
    this.omni = []; this.spot = [];
    for (let i = 0; i < count.omni; i++) { const L = new THREE.PointLight(0xffffff, 0, 1, 2); L.visible = true; root.add(L); this.omni.push(L); }
    for (let i = 0; i < count.spot; i++) { const L = new THREE.SpotLight(0xffffff, 0, 1, 0.8, 0.3, 2); root.add(L, L.target); this.spot.push(L); }
    this.t = 0;
  }
  update(focus, dt) {
    this.t -= dt;
    if (this.t > 0) return;
    this.t = 0.2;
    for (const [pool, type] of [[this.omni, 'omni'], [this.spot, 'spot']]) {
      const near = this.lamps.filter(l => l.type === type)
        .map(l => [l, l.p.distanceTo(focus) - l.range]).sort((a, b) => a[1] - b[1]).slice(0, pool.length);
      pool.forEach((L, i) => {
        const e = near[i];
        if (!e || e[1] > 25) { L.intensity = 0; return; }
        const l = e[0];
        L.position.copy(l.p); L.color.copy(color(l.color));
        L.distance = l.range; L.decay = 2;
        // Godot's falloff ends at `range` and is gentler than inverse square inside it; scaling by range keeps
        // the pool of light about the size it is in Godot.
        L.intensity = l.energy * Math.PI * Math.max(1, l.range * l.range / 16);
        if (type === 'spot') { L.angle = Math.min(l.angle, 1.4); L.target.position.set(l.p.x + l.dir[0], l.p.y + l.dir[1], l.p.z + l.dir[2]); }
      });
    }
  }
}

/** Sky, fog, ambient light and tone mapping from the level's WorldEnvironment. */
export function applyEnvironment(renderer, scene, env, skyDome) {
  const sky = env.sky;
  if (env.background === 'sky' && sky) {
    skyDome.visible = true;
    const u = skyDome.material.uniforms, e = sky.energy ?? 1;
    u.top.value.copy(color(sky.top)).multiplyScalar(e); u.horizon.value.copy(color(sky.horizon)).multiplyScalar(e);
    u.groundHorizon.value.copy(color(sky.ground_horizon)).multiplyScalar(e); u.groundBottom.value.copy(color(sky.ground_bottom)).multiplyScalar(e);
    scene.background = null;
  } else {
    skyDome.visible = false;
    scene.background = color(env.bg_color || [0.1, 0.12, 0.16, 1]).multiplyScalar(env.bg_energy ?? 1);
  }
  scene.fog = !env.fog ? null : env.fog_mode === 'depth'
    ? new THREE.Fog(color(env.fog_color), env.fog_depth_begin, env.fog_depth_end)
    : new THREE.FogExp2(color(env.fog_color), env.fog_density);
  renderer.toneMapping = TONEMAPS[env.tonemap ?? 3] ?? THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = env.exposure ?? 1;
}

/** Ambient light for the environment: a hemisphere from the sky colours, or Godot's flat ambient colour. */
export function ambientFor(env) {
  const e = env.ambient_energy ?? 0.5;
  if ((env.ambient_source === 'sky' || env.ambient_source === 'background') && env.sky) {
    const top = color(env.sky.horizon).lerp(color(env.sky.top), 0.5).multiplyScalar(env.sky.energy ?? 1);
    return new THREE.HemisphereLight(top, color(env.sky.ground_horizon).multiplyScalar(env.sky.energy ?? 1), e * Math.PI);
  }
  if (env.ambient_source === 'color') return new THREE.AmbientLight(color(env.ambient_color), e * Math.PI);
  return new THREE.AmbientLight(0x404040, 0.5);
}

export function makeSkyDome() {
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { top: { value: new THREE.Color() }, horizon: { value: new THREE.Color() }, groundHorizon: { value: new THREE.Color() }, groundBottom: { value: new THREE.Color() } },
    vertexShader: 'varying vec3 vDir; void main(){ vDir = normalize(position); vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0); gl_Position = p.xyww; }',
    fragmentShader: `uniform vec3 top, horizon, groundHorizon, groundBottom; varying vec3 vDir;
      void main(){ float y = vDir.y; vec3 c = y > 0.0 ? mix(horizon, top, pow(clamp(y, 0.0, 1.0), 0.6)) : mix(groundHorizon, groundBottom, pow(clamp(-y, 0.0, 1.0), 0.5));
      gl_FragColor = vec4(c, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      }`,
  });
  const m = new THREE.Mesh(new THREE.SphereGeometry(500, 32, 16), mat);
  m.frustumCulled = false; m.renderOrder = -1;
  return m;
}

export function disposeTree(o) {
  o.traverse(n => {
    if (n.geometry) n.geometry.dispose();
    const mats = n.material ? (Array.isArray(n.material) ? n.material : [n.material]) : [];
    for (const m of mats) { for (const k in m) if (m[k] && m[k].isTexture) m[k].dispose(); m.dispose(); }
  });
}
