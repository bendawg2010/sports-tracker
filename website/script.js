// Sports Tracker — promo site
// No frameworks. Vanilla JS, deferred load.
(function () {
  'use strict';

  // ------------------------------------------------------------------
  // 1. Sport-field SVGs (each as a function returning an inert <svg> Element)
  // ------------------------------------------------------------------
  const SVG_NS = 'http://www.w3.org/2000/svg';

  function svgEl(name, attrs) {
    const el = document.createElementNS(SVG_NS, name);
    if (attrs) for (const k in attrs) el.setAttribute(k, attrs[k]);
    return el;
  }
  function svgText(text, attrs) {
    const t = svgEl('text', attrs);
    t.textContent = text;
    return t;
  }
  function svgGroup(children, attrs) {
    const g = svgEl('g', attrs);
    children.forEach((c) => g.appendChild(c));
    return g;
  }
  function svgDefs(children) {
    const defs = svgEl('defs');
    children.forEach((c) => defs.appendChild(c));
    return defs;
  }
  function linearGradient(id, stops) {
    const lg = svgEl('linearGradient', { id, x1: 0, x2: 0, y1: 0, y2: 1 });
    stops.forEach(([off, color]) => {
      lg.appendChild(svgEl('stop', { offset: off, 'stop-color': color }));
    });
    return lg;
  }
  function radialGradient(id, stops, opts) {
    const rg = svgEl('radialGradient', { id, cx: opts?.cx ?? 0.5, cy: opts?.cy ?? 0.5, r: opts?.r ?? 0.6 });
    stops.forEach(([off, color]) => {
      rg.appendChild(svgEl('stop', { offset: off, 'stop-color': color }));
    });
    return rg;
  }

  // Each sport returns an array of SVG child elements
  const SPORTS = [
    {
      label: 'Football',
      build: () => {
        const out = [];
        out.push(svgDefs([linearGradient('ff-bg', [['0%', '#0e1f12'], ['100%', '#0A0A0C']])]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#ff-bg)' }));
        out.push(svgEl('rect', { x: 20, y: 34, width: 280, height: 172, fill: 'none', stroke: '#4ADE80', 'stroke-width': 1, opacity: 0.5 }));
        out.push(svgEl('rect', { x: 20, y: 34, width: 36, height: 172, fill: 'rgba(74,222,128,0.06)', stroke: '#4ADE80', 'stroke-width': 1, opacity: 0.6 }));
        out.push(svgEl('rect', { x: 264, y: 34, width: 36, height: 172, fill: 'rgba(74,222,128,0.06)', stroke: '#4ADE80', 'stroke-width': 1, opacity: 0.6 }));
        [80, 104, 128, 152, 176, 200, 224, 248].forEach((x) => {
          out.push(svgEl('line', { x1: x, y1: 34, x2: x, y2: 206, stroke: '#4ADE80', 'stroke-width': 0.7, opacity: 0.45 }));
        });
        out.push(svgEl('line', { x1: 160, y1: 34, x2: 160, y2: 206, stroke: '#FFB81C', 'stroke-width': 1, opacity: 0.85 }));
        const numbers = svgGroup([], { 'font-family': 'ui-monospace,monospace', 'font-size': 7, fill: '#4ADE80', opacity: 0.6 });
        [[76, '10'], [100, '20'], [124, '30'], [148, '40'], [172, '40'], [196, '30'], [220, '20'], [244, '10']].forEach(([x, n]) => {
          numbers.appendChild(svgText(n, { x, y: 124, 'text-anchor': 'middle' }));
        });
        out.push(numbers);
        out.push(svgEl('path', { d: 'M80 138 Q 130 120 174 130', fill: 'none', stroke: '#FFB81C', 'stroke-width': 1.5, 'stroke-dasharray': '2 3', opacity: 0.85 }));
        out.push(svgEl('ellipse', { cx: 174, cy: 130, rx: 3.5, ry: 2, fill: '#FFB81C' }));
        return out;
      },
    },
    {
      label: 'Basketball',
      build: () => {
        const out = [];
        out.push(svgDefs([linearGradient('bb-bg', [['0%', '#1a1108'], ['100%', '#0A0A0C']])]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#bb-bg)' }));
        out.push(svgEl('rect', { x: 20, y: 36, width: 280, height: 168, fill: 'none', stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.7 }));
        out.push(svgEl('line', { x1: 160, y1: 36, x2: 160, y2: 204, stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.7 }));
        out.push(svgEl('circle', { cx: 160, cy: 120, r: 22, fill: 'none', stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.7 }));
        out.push(svgEl('path', { d: 'M 20 70 L 60 70 A 60 50 0 0 1 60 170 L 20 170', fill: 'none', stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.55 }));
        out.push(svgEl('path', { d: 'M 300 70 L 260 70 A 60 50 0 0 0 260 170 L 300 170', fill: 'none', stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.55 }));
        out.push(svgEl('rect', { x: 20, y: 92, width: 46, height: 56, fill: 'none', stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.55 }));
        out.push(svgEl('rect', { x: 254, y: 92, width: 46, height: 56, fill: 'none', stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.55 }));
        const dots = [
          [56, 116, '#4DA3FF'], [76, 96, '#4DA3FF'], [92, 148, '#4DA3FF'],
          [120, 80, '#4DA3FF'], [44, 142, '#4DA3FF'],
          [220, 96, '#FF7A7A'], [240, 156, '#FF7A7A'], [278, 118, '#FF7A7A'], [200, 138, '#FF7A7A'],
        ];
        dots.forEach(([cx, cy, fill]) => out.push(svgEl('circle', { cx, cy, r: 2.5, fill })));
        return out;
      },
    },
    {
      label: 'Baseball',
      build: () => {
        const out = [];
        out.push(svgDefs([radialGradient('bd-bg', [['0%', '#0e1a12'], ['100%', '#0A0A0C']], { cx: 0.5, cy: 1, r: 1 })]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#bd-bg)' }));
        out.push(svgEl('path', { d: 'M 40 220 A 200 200 0 0 1 280 220 Z', fill: 'none', stroke: '#4ADE80', 'stroke-width': 0.9, opacity: 0.4 }));
        out.push(svgEl('path', { d: 'M 160 80 L 220 140 L 160 200 L 100 140 Z', fill: 'rgba(255,184,28,0.05)', stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.85 }));
        const bases = [[160, 80], [220, 140], [160, 200], [100, 140]];
        bases.forEach(([cx, cy]) => out.push(svgEl('rect', { x: cx - 4, y: cy - 4, width: 8, height: 8, transform: `rotate(45 ${cx} ${cy})`, fill: '#FFB81C' })));
        out.push(svgEl('circle', { cx: 160, cy: 140, r: 6, fill: 'none', stroke: '#FFB81C', 'stroke-width': 1, opacity: 0.7 }));
        out.push(svgEl('circle', { cx: 160, cy: 80, r: 3.5, fill: '#4DA3FF' }));
        out.push(svgEl('circle', { cx: 220, cy: 140, r: 3.5, fill: '#4DA3FF' }));
        out.push(svgText('B 2 · S 1 · O 2', { x: 160, y: 36, 'text-anchor': 'middle', 'font-family': 'ui-monospace,monospace', 'font-size': 9, fill: '#A1A1A8' }));
        return out;
      },
    },
    {
      label: 'Hockey',
      build: () => {
        const out = [];
        out.push(svgDefs([linearGradient('hk-bg', [['0%', '#0c1622'], ['100%', '#0A0A0C']])]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#hk-bg)' }));
        out.push(svgEl('rect', { x: 20, y: 36, width: 280, height: 168, rx: 44, fill: 'none', stroke: '#7BC0FF', 'stroke-width': 1.1, opacity: 0.6 }));
        out.push(svgEl('line', { x1: 160, y1: 36, x2: 160, y2: 204, stroke: '#FF5C5C', 'stroke-width': 1.4, opacity: 0.85 }));
        out.push(svgEl('line', { x1: 110, y1: 36, x2: 110, y2: 204, stroke: '#4DA3FF', 'stroke-width': 1.1, opacity: 0.7 }));
        out.push(svgEl('line', { x1: 210, y1: 36, x2: 210, y2: 204, stroke: '#4DA3FF', 'stroke-width': 1.1, opacity: 0.7 }));
        out.push(svgEl('line', { x1: 40, y1: 36, x2: 40, y2: 204, stroke: '#FF5C5C', 'stroke-width': 0.8, opacity: 0.5 }));
        out.push(svgEl('line', { x1: 280, y1: 36, x2: 280, y2: 204, stroke: '#FF5C5C', 'stroke-width': 0.8, opacity: 0.5 }));
        out.push(svgEl('circle', { cx: 160, cy: 120, r: 22, fill: 'none', stroke: '#4DA3FF', 'stroke-width': 1, opacity: 0.6 }));
        out.push(svgEl('circle', { cx: 160, cy: 120, r: 2, fill: '#FF5C5C' }));
        [[74, 76], [74, 164], [246, 76], [246, 164]].forEach(([cx, cy]) => {
          out.push(svgEl('circle', { cx, cy, r: 14, fill: 'none', stroke: '#FF5C5C', 'stroke-width': 0.9, opacity: 0.6 }));
        });
        out.push(svgEl('circle', { cx: 48, cy: 120, r: 3, fill: '#FFB81C' }));
        out.push(svgEl('circle', { cx: 272, cy: 120, r: 3, fill: '#FFB81C' }));
        out.push(svgEl('circle', { cx: 272, cy: 100, r: 3, fill: '#FFB81C' }));
        return out;
      },
    },
    {
      label: 'Soccer',
      build: () => {
        const out = [];
        out.push(svgDefs([linearGradient('sc-bg', [['0%', '#0d1a10'], ['100%', '#0A0A0C']])]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#sc-bg)' }));
        out.push(svgEl('rect', { x: 24, y: 36, width: 272, height: 168, fill: 'none', stroke: '#4ADE80', 'stroke-width': 1.1, opacity: 0.55 }));
        out.push(svgEl('line', { x1: 160, y1: 36, x2: 160, y2: 204, stroke: '#4ADE80', 'stroke-width': 1.1, opacity: 0.55 }));
        out.push(svgEl('circle', { cx: 160, cy: 120, r: 28, fill: 'none', stroke: '#4ADE80', 'stroke-width': 1.1, opacity: 0.55 }));
        out.push(svgEl('circle', { cx: 160, cy: 120, r: 2, fill: '#4ADE80' }));
        out.push(svgEl('rect', { x: 24, y: 76, width: 38, height: 88, fill: 'none', stroke: '#4ADE80', 'stroke-width': 1, opacity: 0.5 }));
        out.push(svgEl('rect', { x: 258, y: 76, width: 38, height: 88, fill: 'none', stroke: '#4ADE80', 'stroke-width': 1, opacity: 0.5 }));
        out.push(svgEl('rect', { x: 24, y: 100, width: 14, height: 40, fill: 'none', stroke: '#4ADE80', 'stroke-width': 0.8, opacity: 0.45 }));
        out.push(svgEl('rect', { x: 282, y: 100, width: 14, height: 40, fill: 'none', stroke: '#4ADE80', 'stroke-width': 0.8, opacity: 0.45 }));
        out.push(svgEl('path', { d: 'M 62 102 A 18 18 0 0 1 62 138', fill: 'none', stroke: '#4ADE80', 'stroke-width': 0.8, opacity: 0.45 }));
        out.push(svgEl('path', { d: 'M 258 102 A 18 18 0 0 0 258 138', fill: 'none', stroke: '#4ADE80', 'stroke-width': 0.8, opacity: 0.45 }));
        out.push(svgEl('circle', { cx: 42, cy: 116, r: 3, fill: '#FFB81C' }));
        out.push(svgEl('circle', { cx: 278, cy: 124, r: 3, fill: '#4DA3FF' }));
        out.push(svgEl('circle', { cx: 278, cy: 100, r: 3, fill: '#4DA3FF' }));
        out.push(svgText("87'", { x: 160, y: 120, 'text-anchor': 'middle', 'dominant-baseline': 'middle', 'font-family': 'ui-monospace,monospace', 'font-size': 9, fill: '#FFB81C', 'font-weight': 700 }));
        return out;
      },
    },
    {
      label: 'Tennis',
      build: () => {
        const out = [];
        out.push(svgDefs([linearGradient('tn-bg', [['0%', '#1a2218'], ['100%', '#0A0A0C']])]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#tn-bg)' }));
        out.push(svgEl('rect', { x: 60, y: 40, width: 200, height: 160, fill: 'none', stroke: '#FFB81C', 'stroke-width': 1.1, opacity: 0.65 }));
        out.push(svgEl('line', { x1: 78, y1: 40, x2: 78, y2: 200, stroke: '#FFB81C', 'stroke-width': 0.9, opacity: 0.55 }));
        out.push(svgEl('line', { x1: 242, y1: 40, x2: 242, y2: 200, stroke: '#FFB81C', 'stroke-width': 0.9, opacity: 0.55 }));
        out.push(svgEl('line', { x1: 60, y1: 120, x2: 260, y2: 120, stroke: '#4DA3FF', 'stroke-width': 1.4, opacity: 0.85 }));
        out.push(svgEl('line', { x1: 78, y1: 80, x2: 242, y2: 80, stroke: '#FFB81C', 'stroke-width': 0.9, opacity: 0.55 }));
        out.push(svgEl('line', { x1: 78, y1: 160, x2: 242, y2: 160, stroke: '#FFB81C', 'stroke-width': 0.9, opacity: 0.55 }));
        out.push(svgEl('line', { x1: 160, y1: 80, x2: 160, y2: 160, stroke: '#FFB81C', 'stroke-width': 0.9, opacity: 0.55 }));
        out.push(svgEl('rect', { x: 160, y: 80, width: 82, height: 40, fill: 'rgba(255,184,28,0.12)' }));
        out.push(svgEl('circle', { cx: 200, cy: 100, r: 3, fill: '#E1FF6A' }));
        out.push(svgText('DJOKOVIC  6  4  3', { x: 78, y: 32, 'font-family': 'ui-monospace,monospace', 'font-size': 8, fill: '#A1A1A8' }));
        out.push(svgText('ALCARAZ   3  6  4', { x: 78, y: 220, 'font-family': 'ui-monospace,monospace', 'font-size': 8, fill: '#A1A1A8' }));
        return out;
      },
    },
    {
      label: 'Golf',
      build: () => {
        const out = [];
        out.push(svgDefs([radialGradient('gf-bg', [['0%', '#0f1a12'], ['100%', '#0A0A0C']], { cx: 0.5, cy: 0.4, r: 0.8 })]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#gf-bg)' }));
        out.push(svgEl('path', { d: 'M 40 200 Q 80 140 130 130 Q 200 120 220 60', fill: 'none', stroke: '#4ADE80', 'stroke-width': 14, 'stroke-linecap': 'round', opacity: 0.18 }));
        out.push(svgEl('path', { d: 'M 40 200 Q 80 140 130 130 Q 200 120 220 60', fill: 'none', stroke: '#4ADE80', 'stroke-width': 2, 'stroke-linecap': 'round', opacity: 0.55 }));
        out.push(svgEl('ellipse', { cx: 100, cy: 180, rx: 22, ry: 10, fill: 'none', stroke: '#FFB81C', 'stroke-width': 0.9, opacity: 0.45, 'stroke-dasharray': '2 2' }));
        out.push(svgEl('ellipse', { cx: 190, cy: 100, rx: 14, ry: 8, fill: 'none', stroke: '#FFB81C', 'stroke-width': 0.9, opacity: 0.45, 'stroke-dasharray': '2 2' }));
        out.push(svgEl('path', { d: 'M 60 100 Q 90 90 110 110 Q 100 130 80 120 Z', fill: 'rgba(77,163,255,0.18)', stroke: '#4DA3FF', 'stroke-width': 0.8, opacity: 0.55 }));
        out.push(svgEl('circle', { cx: 40, cy: 200, r: 3, fill: '#FFB81C' }));
        out.push(svgText('TEE', { x: 46, y: 214, 'font-family': 'ui-monospace,monospace', 'font-size': 7, fill: '#A1A1A8' }));
        out.push(svgEl('circle', { cx: 220, cy: 60, r: 14, fill: 'none', stroke: '#4ADE80', 'stroke-width': 1, opacity: 0.7 }));
        out.push(svgEl('circle', { cx: 220, cy: 60, r: 2, fill: '#FFB81C' }));
        out.push(svgEl('line', { x1: 220, y1: 60, x2: 220, y2: 34, stroke: '#FFB81C', 'stroke-width': 1 }));
        out.push(svgEl('path', { d: 'M 220 34 L 232 38 L 220 42 Z', fill: '#FF5C5C' }));
        out.push(svgText('SCHEFFLER −12', { x: 20, y: 32, 'font-family': 'ui-monospace,monospace', 'font-size': 8, fill: '#FFB81C', 'font-weight': 700 }));
        return out;
      },
    },
    {
      label: 'Formula 1',
      build: () => {
        const out = [];
        out.push(svgDefs([linearGradient('f1-bg', [['0%', '#1a0d10'], ['100%', '#0A0A0C']])]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#f1-bg)' }));
        const rows = [
          ['1', 'VER', 'RBR', 'LEADER'],
          ['2', 'HAM', 'MER', '+0.812'],
          ['3', 'LEC', 'FER', '+1.245'],
          ['4', 'NOR', 'MCL', '+1.998'],
          ['5', 'RUS', 'MER', '+3.112'],
          ['6', 'SAI', 'FER', '+4.020'],
          ['7', 'PIA', 'MCL', '+5.667'],
          ['8', 'PER', 'RBR', '+6.890'],
        ];
        const teamColors = { RBR: '#1E3F8C', MER: '#00D2BE', FER: '#DC0000', MCL: '#FF8700' };
        const tower = svgGroup([], { 'font-family': 'ui-monospace,monospace', 'font-size': 9, fill: '#F5F5F7' });
        rows.forEach((row, i) => {
          const y = 50 + i * 22;
          const teamColor = teamColors[row[2]] || '#A1A1A8';
          tower.appendChild(svgEl('rect', { x: 20, y: y - 13, width: 280, height: 18, fill: 'rgba(255,255,255,0.02)', stroke: 'rgba(255,255,255,0.05)', 'stroke-width': 0.5 }));
          tower.appendChild(svgEl('rect', { x: 20, y: y - 13, width: 3, height: 18, fill: teamColor }));
          tower.appendChild(svgText('P' + row[0], { x: 34, y, fill: '#FFB81C', 'font-weight': 700 }));
          tower.appendChild(svgText(row[1], { x: 60, y, 'font-weight': 600 }));
          tower.appendChild(svgText(row[2], { x: 100, y, fill: teamColor, 'font-size': 8 }));
          tower.appendChild(svgText(row[3], { x: 290, y, 'text-anchor': 'end', fill: row[3] === 'LEADER' ? '#FFB81C' : '#A1A1A8' }));
        });
        out.push(tower);
        out.push(svgText('LAP 41/57 · MONACO', { x: 20, y: 34, 'font-family': 'ui-monospace,monospace', 'font-size': 9, fill: '#A1A1A8' }));
        return out;
      },
    },
    {
      label: 'UFC',
      build: () => {
        const out = [];
        out.push(svgDefs([
          radialGradient('uf-bg', [['0%', '#1a1108'], ['100%', '#0A0A0C']], { r: 0.7 }),
          radialGradient('uf-glow', [['0%', 'rgba(255,184,28,0.18)'], ['100%', 'rgba(255,184,28,0)']], { r: 0.5 }),
        ]));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#uf-bg)' }));
        out.push(svgEl('rect', { width: 320, height: 240, fill: 'url(#uf-glow)' }));
        out.push(svgEl('polygon', { points: '160,40 244,84 244,156 160,200 76,156 76,84', fill: 'rgba(255,184,28,0.04)', stroke: '#FFB81C', 'stroke-width': 1.4, opacity: 0.85 }));
        out.push(svgEl('polygon', { points: '160,52 232,90 232,150 160,188 88,150 88,90', fill: 'none', stroke: '#FFB81C', 'stroke-width': 0.6, opacity: 0.45 }));
        out.push(svgEl('circle', { cx: 160, cy: 120, r: 3, fill: '#FFB81C' }));
        out.push(svgEl('circle', { cx: 106, cy: 98, r: 6, fill: 'none', stroke: '#4DA3FF', 'stroke-width': 1.4, opacity: 0.85 }));
        out.push(svgEl('circle', { cx: 214, cy: 142, r: 6, fill: 'none', stroke: '#FF5C5C', 'stroke-width': 1.4, opacity: 0.85 }));
        out.push(svgText('R3 · 2:14', { x: 160, y: 34, 'text-anchor': 'middle', 'font-family': 'ui-monospace,monospace', 'font-size': 8, fill: '#A1A1A8' }));
        out.push(svgText('JONES 38 STR', { x: 20, y: 218, 'font-family': 'ui-monospace,monospace', 'font-size': 8, fill: '#4DA3FF' }));
        out.push(svgText('MIOCIC 24 STR', { x: 300, y: 218, 'text-anchor': 'end', 'font-family': 'ui-monospace,monospace', 'font-size': 8, fill: '#FF5C5C' }));
        return out;
      },
    },
  ];

  function injectSports() {
    const grid = document.getElementById('sportGrid');
    if (!grid) return;
    const frag = document.createDocumentFragment();
    SPORTS.forEach((s) => {
      const article = document.createElement('article');
      article.className = 'sport-card';
      article.setAttribute('aria-label', s.label + ' field');

      const svg = svgEl('svg', {
        viewBox: '0 0 320 240',
        preserveAspectRatio: 'xMidYMid slice',
        role: 'img',
        'aria-hidden': 'true',
      });
      s.build().forEach((child) => svg.appendChild(child));
      article.appendChild(svg);

      const label = document.createElement('span');
      label.className = 'label';
      label.textContent = s.label;
      article.appendChild(label);

      frag.appendChild(article);
    });
    grid.appendChild(frag);
  }

  // ------------------------------------------------------------------
  // 2. Sticky nav scroll-spy + scrolled-state
  // ------------------------------------------------------------------
  function initNav() {
    const nav = document.getElementById('siteNav');
    const links = document.querySelectorAll('.nav-links a[href^="#"]');
    const sections = Array.from(links)
      .map((a) => {
        const id = a.getAttribute('href').slice(1);
        return id ? document.getElementById(id) : null;
      })
      .filter(Boolean);

    const onScroll = () => {
      if (window.scrollY > 12) nav.classList.add('is-scrolled');
      else nav.classList.remove('is-scrolled');

      const y = window.scrollY + 120;
      let activeIdx = -1;
      for (let i = 0; i < sections.length; i++) {
        if (sections[i].offsetTop <= y) activeIdx = i;
      }
      links.forEach((l) => l.classList.remove('is-active'));
      if (activeIdx >= 0) {
        const id = sections[activeIdx].id;
        document.querySelectorAll('.nav-links a[href="#' + id + '"]').forEach((l) => l.classList.add('is-active'));
      }
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();

    const toggle = document.getElementById('navToggle');
    const links2 = document.getElementById('navLinks');
    if (toggle && links2) {
      toggle.addEventListener('click', () => {
        const open = links2.classList.toggle('is-open');
        toggle.setAttribute('aria-expanded', String(open));
      });
      links2.addEventListener('click', (e) => {
        if (e.target.tagName === 'A') {
          links2.classList.remove('is-open');
          toggle.setAttribute('aria-expanded', 'false');
        }
      });
    }
  }

  // ------------------------------------------------------------------
  // 3. Intersection-observer fade-ins
  // ------------------------------------------------------------------
  function initReveal() {
    const els = document.querySelectorAll('.reveal');
    if (!('IntersectionObserver' in window)) {
      els.forEach((el) => el.classList.add('is-visible'));
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible');
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: '0px 0px -8% 0px' }
    );
    els.forEach((el) => io.observe(el));
  }

  // ------------------------------------------------------------------
  // 4. FAQ accordion (one-open-at-a-time on top of native <details>)
  // ------------------------------------------------------------------
  function initFAQ() {
    const items = document.querySelectorAll('.faq-item');
    items.forEach((item) => {
      item.addEventListener('toggle', () => {
        if (item.open) {
          item.classList.add('is-open');
          items.forEach((other) => {
            if (other !== item && other.open) {
              other.open = false;
              other.classList.remove('is-open');
            }
          });
        } else {
          item.classList.remove('is-open');
        }
      });
    });
  }

  // ------------------------------------------------------------------
  // 5. Theme toggle (persisted to localStorage)
  // ------------------------------------------------------------------
  function initTheme() {
    const root = document.documentElement;
    const btn = document.getElementById('themeToggle');
    let saved = null;
    try { saved = localStorage.getItem('st-theme'); } catch (e) {}
    if (saved === 'light' || saved === 'dark') root.setAttribute('data-theme', saved);

    if (!btn) return;
    btn.addEventListener('click', () => {
      const cur = root.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
      const next = cur === 'light' ? 'dark' : 'light';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('st-theme', next); } catch (e) {}
    });
  }

  // ------------------------------------------------------------------
  // 6. Donate modal
  // ------------------------------------------------------------------
  function initDonate() {
    const modal = document.getElementById('donateModal');
    const close = document.getElementById('donateClose');
    if (!modal || !close) return;

    const open = () => {
      modal.classList.add('is-open');
      modal.setAttribute('aria-hidden', 'false');
      document.body.style.overflow = 'hidden';
    };
    const hide = () => {
      modal.classList.remove('is-open');
      modal.setAttribute('aria-hidden', 'true');
      document.body.style.overflow = '';
    };

    document.querySelectorAll('.js-open-donate').forEach((el) => {
      el.addEventListener('click', (e) => {
        e.preventDefault();
        open();
      });
    });
    close.addEventListener('click', hide);
    modal.addEventListener('click', (e) => { if (e.target === modal) hide(); });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') hide(); });
  }

  // ------------------------------------------------------------------
  // 7. Year + tiny niceties
  // ------------------------------------------------------------------
  function initYear() {
    const y = document.getElementById('year');
    if (y) y.textContent = String(new Date().getFullYear());
  }

  // ------------------------------------------------------------------
  // 8. Subtle parallax on hero mockup (mouse move)
  // ------------------------------------------------------------------
  function initParallax() {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    if (window.matchMedia('(max-width: 900px)').matches) return;
    const mockup = document.querySelector('.mockup');
    if (!mockup) return;
    let frame = 0;
    document.addEventListener('mousemove', (e) => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const x = (e.clientX / window.innerWidth - 0.5) * 6;
        const y = (e.clientY / window.innerHeight - 0.5) * 6;
        mockup.style.transform = 'translate3d(' + (-x) + 'px,' + (-y) + 'px,0)';
      });
    }, { passive: true });
  }

  // ------------------------------------------------------------------
  // Boot
  // ------------------------------------------------------------------
  function boot() {
    injectSports();
    initNav();
    initReveal();
    initFAQ();
    initTheme();
    initDonate();
    initYear();
    initParallax();
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
