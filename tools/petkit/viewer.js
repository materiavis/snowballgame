/* Kleiner WebGL2-Betrachter fuer die .glb-Dateien aus petkit. Keine Abhaengigkeiten. */
function parseGLB(buf) {
  const dv = new DataView(buf);
  if (dv.getUint32(0, true) !== 0x46546c67) throw new Error('Keine GLB-Datei');
  const jl = dv.getUint32(12, true);
  const j = JSON.parse(new TextDecoder().decode(new Uint8Array(buf, 20, jl)));
  const binStart = 20 + jl + 8;
  const view = (i) => { const v = j.bufferViews[i]; return [binStart + (v.byteOffset || 0), v.byteLength]; };
  const acc = (i, T, n) => { const a = j.accessors[i]; const [o] = view(a.bufferView); return new T(buf, o, a.count * n); };
  const p = j.meshes[0].primitives[0];
  const [io, il] = view(j.images[0].bufferView);
  return {
    name: j.meshes[0].name,
    pos: acc(p.attributes.POSITION, Float32Array, 3), nrm: acc(p.attributes.NORMAL, Float32Array, 3),
    uv: acc(p.attributes.TEXCOORD_0, Float32Array, 2), idx: acc(p.indices, Uint16Array, 1),
    png: new Blob([new Uint8Array(buf, io, il)], { type: 'image/png' }),
    min: j.accessors[p.attributes.POSITION].min, max: j.accessors[p.attributes.POSITION].max,
  };
}
const M4 = {
  persp(f, a, n, r) { const t = 1 / Math.tan(f / 2); return [t / a, 0, 0, 0, 0, t, 0, 0, 0, 0, (r + n) / (n - r), -1, 0, 0, 2 * r * n / (n - r), 0]; },
  mul(a, b) { const o = new Array(16).fill(0); for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) for (let k = 0; k < 4; k++) o[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k]; return o; },
  look(e, c, u) {
    const z = V3.norm(V3.sub(e, c)), x = V3.norm(V3.cross(u, z)), y = V3.cross(z, x);
    return [x[0], y[0], z[0], 0, x[1], y[1], z[1], 0, x[2], y[2], z[2], 0, -V3.dot(x, e), -V3.dot(y, e), -V3.dot(z, e), 1];
  },
};
const V3 = {
  sub: (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]], dot: (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
  cross: (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
  norm: (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; },
};
const VS = `#version 300 es
layout(location=0) in vec3 aP; layout(location=1) in vec3 aN; layout(location=2) in vec2 aU;
uniform mat4 uVP; uniform vec4 uHop; out vec3 vN; out vec3 vW; out vec2 vU;
void main(){ vec3 p=aP; float h=uHop.w; p.y*=uHop.x; p.xz*=uHop.y; p.y+=uHop.z;
 vN=aN; vW=p; vU=aU; gl_Position=uVP*vec4(p,1.0); }`;
const FS = `#version 300 es
precision highp float; in vec3 vN; in vec3 vW; in vec2 vU; out vec4 o;
uniform sampler2D uT; uniform vec3 uEye; uniform mat3 uEyeRot;
vec3 toLin(vec3 c){return pow(c,vec3(2.2));} vec3 toS(vec3 c){return pow(max(c,vec3(0.)),vec3(1./2.2));}
void main(){ vec3 N=normalize(vN), V=normalize(uEye-vW);
 vec3 L=normalize(uEyeRot*vec3(-.5,.75,.7)); vec3 F=normalize(uEyeRot*vec3(.8,.15,.45));
 float w=.4; float d=clamp((dot(N,L)+w)/(1.+w),0.,1.); d=d*d*(3.-2.*d);
 float f=clamp((dot(N,F)+.3)/1.3,0.,1.);
 vec3 amb=mix(vec3(.58,.63,.76),vec3(.80,.85,.95),N.y*.5+.5);
 vec3 base=toLin(texture(uT,vU).rgb);
 vec3 c=base*(amb*.70+vec3(1.,.97,.92)*d*.40+vec3(.65,.75,1.)*f*.06);
 float s=pow(max(dot(N,normalize(L+V)),0.),40.)*.05; c+=vec3(s);
 float r=pow(1.-max(dot(N,V),0.),3.); c+=vec3(.75,.85,1.)*r*.10;
 c=c/(1.+max(c-.72,0.)*.55); o=vec4(toS(c),1.); }`;
const VS2 = `#version 300 es
layout(location=0) in vec2 aP; uniform mat4 uVP; uniform vec3 uS; out vec2 vP;
void main(){ vP=aP; gl_Position=uVP*vec4(aP.x*uS.x,0.002,aP.y*uS.y,1.); }`;
const FS2 = `#version 300 es
precision highp float; in vec2 vP; uniform float uA; uniform vec3 uC; out vec4 o;
void main(){ float r=length(vP); float a=smoothstep(1.,.15,r); a=a*a*uA; o=vec4(uC*a,a); }`;

class PetStage {
  constructor(canvas, opt = {}) {
    this.c = canvas; this.opt = opt;
    const gl = this.gl = canvas.getContext('webgl2', { antialias: true, alpha: true, premultipliedAlpha: true, preserveDrawingBuffer: !!opt.keep });
    if (!gl) { this.failed = true; return; }
    this.yaw = opt.yaw ?? -0.5; this.pitch = opt.pitch ?? 0.16; this.dist = 8.2; this.vy = 0; this.vp = 0;
    this.auto = opt.auto !== false; this.hop = false; this.t0 = performance.now(); this.h = 3.5;
    const prog = (v, f) => {
      const p = gl.createProgram();
      for (const [t, s] of [[gl.VERTEX_SHADER, v], [gl.FRAGMENT_SHADER, f]]) {
        const h = gl.createShader(t); gl.shaderSource(h, s); gl.compileShader(h);
        if (!gl.getShaderParameter(h, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(h));
        gl.attachShader(p, h);
      }
      gl.linkProgram(p); return p;
    };
    this.p1 = prog(VS, FS); this.p2 = prog(VS2, FS2);
    this.quad = gl.createVertexArray(); gl.bindVertexArray(this.quad);
    const b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.enable(gl.DEPTH_TEST); gl.enable(gl.CULL_FACE);
    this.bind(); this.resize();
    this.ro = new ResizeObserver(() => { this.resize(); this.dirty = true; }); this.ro.observe(canvas);
    const loop = () => { this.frame(); this.raf = requestAnimationFrame(loop); }; this.raf = requestAnimationFrame(loop);
  }
  bind() {
    const c = this.c; let drag = null;
    c.addEventListener('pointerdown', (e) => { drag = [e.clientX, e.clientY]; c.setPointerCapture(e.pointerId); this.auto = false; c.classList.add('drag'); this.opt.onTouch && this.opt.onTouch(); });
    c.addEventListener('pointermove', (e) => { if (!drag) return; const dx = e.clientX - drag[0], dy = e.clientY - drag[1]; drag = [e.clientX, e.clientY]; this.vy = dx * 0.008; this.vp = dy * 0.006; this.yaw -= this.vy; this.pitch = Math.max(-0.25, Math.min(1.3, this.pitch + this.vp)); });
    const up = () => { drag = null; c.classList.remove('drag'); }; c.addEventListener('pointerup', up); c.addEventListener('pointercancel', up);
    c.addEventListener('wheel', (e) => { e.preventDefault(); this.dist = Math.max(4.5, Math.min(18, this.dist * Math.exp(e.deltaY * 0.001))); }, { passive: false });
  }
  resize() { const r = this.c.getBoundingClientRect(), d = Math.min(devicePixelRatio || 1, 2); this.c.width = Math.max(1, r.width * d | 0); this.c.height = Math.max(1, r.height * d | 0); }
  async setModel(m) {
    const gl = this.gl; if (!gl) return;
    if (this.vao) gl.deleteVertexArray(this.vao);
    this.vao = gl.createVertexArray(); gl.bindVertexArray(this.vao);
    for (const [i, arr, n] of [[0, m.pos, 3], [1, m.nrm, 3], [2, m.uv, 2]]) {
      const b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b); gl.bufferData(gl.ARRAY_BUFFER, arr, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(i); gl.vertexAttribPointer(i, n, gl.FLOAT, false, 0, 0);
    }
    const ib = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, m.idx, gl.STATIC_DRAW);
    this.n = m.idx.length; this.h = m.max[1]; this.w = Math.max(m.max[0] - m.min[0], m.max[2] - m.min[2]);
    const maxDim = Math.max(m.max[1], m.max[0] - m.min[0], m.max[2] - m.min[2]); this.dist = Math.max(8.2, maxDim * 2.5);
    const img = await createImageBitmap(m.png, { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
    const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    this.tex = t; this.ready = true;
  }
  async setTexture(blob) {
    const gl = this.gl; if (!gl || !this.tex) return;
    const img = await createImageBitmap(blob, { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
    gl.bindTexture(gl.TEXTURE_2D, this.tex); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
  }
  view(y, p) { this.auto = false; this.ty = y; this.tp = p; }
  frame() {
    const gl = this.gl; if (!this.ready) return;
    const now = performance.now(), t = (now - this.t0) / 1000;
    if (this.auto) this.yaw += 0.004;
    if (this.ty !== undefined) { this.yaw += (this.ty - this.yaw) * 0.14; this.pitch += (this.tp - this.pitch) * 0.14; if (Math.abs(this.ty - this.yaw) < 0.002) this.ty = undefined; }
    else if (Math.abs(this.vy) > 0.0005) { this.yaw -= this.vy; this.vy *= 0.92; }
    if (this.c.width < 2) return;
    gl.viewport(0, 0, this.c.width, this.c.height); gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    const c = [0, this.h * 0.47, 0], d = this.dist;
    const e = [c[0] + d * Math.sin(this.yaw) * Math.cos(this.pitch), c[1] + d * Math.sin(this.pitch), c[2] + d * Math.cos(this.yaw) * Math.cos(this.pitch)];
    const vp = M4.mul(M4.persp(0.5, this.c.width / this.c.height, 0.1, 60), M4.look(e, c, [0, 1, 0]));
    let hop = [1, 1, 0, 0];
    if (this.hop) { const s = Math.abs(Math.sin(t * 4.2)), sq = 1 + 0.07 * (s - 0.4); hop = [sq, 1 / Math.sqrt(sq), s * 0.62, 0]; }
    gl.disable(gl.CULL_FACE); gl.depthMask(false); gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    gl.useProgram(this.p2); gl.bindVertexArray(this.quad);
    gl.uniformMatrix4fv(gl.getUniformLocation(this.p2, 'uVP'), false, vp);
    const sh = 1 + hop[2] * 0.25; gl.uniform3f(gl.getUniformLocation(this.p2, 'uS'), this.w * 0.7 * sh, this.w * 0.7 * sh, 1);
    gl.uniform1f(gl.getUniformLocation(this.p2, 'uA'), (this.opt.shadowAlpha ?? 0.34) / sh); const sc = this.opt.shadowColor || [0.24, 0.32, 0.5];
    gl.uniform3f(gl.getUniformLocation(this.p2, 'uC'), sc[0], sc[1], sc[2]);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    gl.depthMask(true); gl.disable(gl.BLEND); gl.enable(gl.CULL_FACE);
    gl.useProgram(this.p1); gl.bindVertexArray(this.vao); gl.bindTexture(gl.TEXTURE_2D, this.tex);
    gl.uniformMatrix4fv(gl.getUniformLocation(this.p1, 'uVP'), false, vp);
    gl.uniform3f(gl.getUniformLocation(this.p1, 'uEye'), e[0], e[1], e[2]);
    const cy = Math.cos(this.yaw), sy = Math.sin(this.yaw);
    gl.uniformMatrix3fv(gl.getUniformLocation(this.p1, 'uEyeRot'), false, [cy, 0, -sy, 0, 1, 0, sy, 0, cy]);
    gl.uniform4f(gl.getUniformLocation(this.p1, 'uHop'), hop[0], hop[1], hop[2], 0);
    gl.drawElements(gl.TRIANGLES, this.n, gl.UNSIGNED_SHORT, 0);
    this.frames = (this.frames || 0) + 1;
  }
}
