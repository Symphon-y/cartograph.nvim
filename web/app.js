/* cartograph web UI — a live, two-way view of the engine's graph.
 *
 * Neovim is the brain: it pushes graph updates over SSE; clicking a node POSTs
 * an action back (expand the next hop, reveal in the editor). This shell owns
 * transport, search, layer/kind filters and theming; the actual drawing lives in
 * a swappable renderer (renderer_3d.js by default, renderer_cy.js for 2D) chosen
 * by the `?renderer` param. Renderers share one interface:
 *   { merge, renderCompare, search, applyFilters, fit, relayout }.
 */
(function () {
  'use strict';

  var params = new URLSearchParams(window.location.search);
  var token = params.get('token') || '';
  var theme = params.get('theme') || 'auto';
  var renderer = params.get('renderer') || '3d';
  var layout = params.get('layout') || 'dagre';

  var resolvedTheme =
    theme === 'auto'
      ? window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'dark'
        : 'light'
      : theme;

  // Colour palettes. CLEAN layer is the primary colour key (every node gets a
  // layer via the engine's kind fallback); compare side overrides it.
  var KIND_COLOR = {
    endpoint: '#ef4444',
    controller: '#3b82f6',
    action: '#8b5cf6',
    service: '#10b981',
    store: '#f59e0b',
    type: '#14b8a6',
    field: '#6b7280',
    call: '#64748b',
  };
  var LAYER_COLOR = {
    UI: '#f59e0b',
    Adapters: '#3b82f6',
    Application: '#8b5cf6',
    Domain: '#10b981',
    Infrastructure: '#64748b',
    unknown: '#6b7280',
  };
  var SIDE_COLOR = { a: '#3b82f6', b: '#f59e0b', both: '#22c55e' };
  var LAYER_ORDER = ['UI', 'Adapters', 'Application', 'Domain', 'Infrastructure', 'unknown'];

  // A tiny glyph per node kind so a label reads as "what it is" at a glance.
  var KIND_GLYPH = {
    endpoint: '◉',
    controller: '⬡',
    class: '⬡',
    action: 'ƒ',
    function: 'ƒ',
    method: 'ƒ',
    service: '⚙',
    store: '▤',
    type: '◇',
    interface: '◇',
    enum: '◇',
    struct: '◇',
    module: '▦',
    field: '•',
    call: '·',
  };

  function colorForNode(d) {
    if (!d) return LAYER_COLOR.unknown;
    if (d.side) return SIDE_COLOR[d.side] || LAYER_COLOR.unknown;
    if (d.layer) return LAYER_COLOR[d.layer] || LAYER_COLOR.unknown;
    return KIND_COLOR[d.kind] || LAYER_COLOR.unknown;
  }

  // The visible label for a node: a kind glyph + its name.
  function labelFor(d) {
    if (!d) return '';
    var g = KIND_GLYPH[d.kind];
    return (g ? g + ' ' : '') + (d.name || '');
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  // ---- transport ----------------------------------------------------------

  function withToken(path) {
    return path + (path.indexOf('?') === -1 ? '?' : '&') + 'token=' + encodeURIComponent(token);
  }
  function send(action, p) {
    var body = Object.assign({ action: action }, p || {});
    return fetch(withToken('/api/message'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).catch(function (err) {
      setStatus('request failed: ' + (err && err.message ? err.message : String(err)));
    });
  }
  function setStatus(msg) {
    document.getElementById('status').textContent = msg;
  }

  // ---- filters (layer + kind) --------------------------------------------

  var seenLayers = {};
  var seenKinds = {};
  var disabledLayers = {};
  var disabledKinds = {};
  var pathFilters = []; // lowercased path fragments to hide
  var view = null;

  function noteNode(n) {
    seenLayers[n.layer || 'unknown'] = true;
    if (n.kind) seenKinds[n.kind] = true;
  }

  function enabledMap(seen, disabled) {
    var m = {};
    Object.keys(seen).forEach(function (k) {
      m[k] = !disabled[k];
    });
    return m;
  }

  function applyActiveFilters() {
    if (!view) return;
    view.applyFilters({
      layers: enabledMap(seenLayers, disabledLayers),
      kinds: enabledMap(seenKinds, disabledKinds),
      paths: pathFilters,
    });
  }

  function chip(label, color, isOff, onToggle) {
    var b = document.createElement('button');
    b.className = 'chip' + (isOff ? ' off' : '');
    b.innerHTML = '<span class="dot" style="background:' + color + '"></span>' + label;
    b.addEventListener('click', function () {
      var off = b.classList.toggle('off');
      onToggle(off);
      applyActiveFilters();
    });
    return b;
  }

  function buildFilters() {
    var el = document.getElementById('filters');
    el.innerHTML = '';
    var layers = document.createElement('div');
    layers.className = 'filter-group';
    LAYER_ORDER.concat(Object.keys(seenLayers)).forEach(function (l) {
      if (!seenLayers[l] || layers.querySelector('[data-l="' + l + '"]')) return;
      var c = chip(l, LAYER_COLOR[l] || LAYER_COLOR.unknown, !!disabledLayers[l], function (off) {
        disabledLayers[l] = off;
      });
      c.setAttribute('data-l', l);
      layers.appendChild(c);
    });
    var kinds = document.createElement('div');
    kinds.className = 'filter-group';
    Object.keys(seenKinds)
      .sort()
      .forEach(function (k) {
        kinds.appendChild(
          chip(k, KIND_COLOR[k] || LAYER_COLOR.unknown, !!disabledKinds[k], function (off) {
            disabledKinds[k] = off;
          })
        );
      });
    el.appendChild(layers);
    el.appendChild(kinds);
  }

  // ---- ingest -------------------------------------------------------------

  function ingest(graph) {
    if (!graph) return;
    (graph.nodes || []).forEach(noteNode);
    buildFilters();
    view.merge(graph);
    applyActiveFilters();
  }

  function ingestCompare(diff) {
    (diff.nodes || []).forEach(noteNode);
    buildFilters();
    view.renderCompare(diff);
    applyActiveFilters();
    var s = diff.summary || {};
    setStatus('compare: ' + (s.shared || 0) + ' shared · ' + (s.only_a || 0) + ' only-A · ' + (s.only_b || 0) + ' only-B');
  }

  // ---- node detail panel (hover) -----------------------------------------

  function showDetail(d) {
    var panel = document.getElementById('detail');
    if (!d) {
      panel.classList.remove('open');
      return;
    }
    var line = d.line != null ? ':' + (d.line + 1) : '';
    var meta = [];
    if (d.layer) meta.push(d.layer);
    if (d.lang) meta.push(d.lang);
    var html =
      '<div class="d-title">' +
      (d.kind ? '<span class="d-kind">' + escapeHtml(d.kind) + '</span>' : '') +
      '<span>' +
      escapeHtml(d.name || '') +
      '</span></div>';
    if (meta.length) html += '<div class="d-meta">' + escapeHtml(meta.join(' · ')) + '</div>';
    if (d.file) html += '<div class="d-meta">' + escapeHtml(d.file + line) + '</div>';
    if (d.snippet) html += '<pre>' + escapeHtml(d.snippet) + '</pre>';
    panel.innerHTML = html;
    panel.classList.add('open');
  }

  // ---- focus / trace breadcrumb ------------------------------------------

  function renderBreadcrumb(path) {
    var el = document.getElementById('breadcrumb');
    el.innerHTML = '';
    if (!path || !path.length) {
      el.classList.remove('open');
      return;
    }
    var clear = document.createElement('button');
    clear.className = 'crumb crumb-clear';
    clear.textContent = '✕';
    clear.title = 'Clear focus';
    clear.addEventListener('click', function () {
      send('clearFocus');
    });
    el.appendChild(clear);
    path.forEach(function (p, i) {
      if (i > 0) {
        var sep = document.createElement('span');
        sep.className = 'crumb-sep';
        sep.textContent = '›';
        el.appendChild(sep);
      }
      var b = document.createElement('button');
      b.className = 'crumb' + (i === path.length - 1 ? ' crumb-tail' : '');
      b.textContent = (KIND_GLYPH[p.kind] ? KIND_GLYPH[p.kind] + ' ' : '') + p.name;
      b.addEventListener('click', function () {
        send('focus', { nodeId: p.id }); // truncates to this step (focus.step)
      });
      el.appendChild(b);
    });
    el.classList.add('open');
  }

  function applyFocus(overlay) {
    if (view) view.applyFocus(overlay);
    renderBreadcrumb(overlay && overlay.path);
  }

  // ---- ambiguity pick-list ------------------------------------------------

  function showChoices(d) {
    var panel = document.getElementById('choices');
    panel.innerHTML = '';
    if (!d.candidates || d.candidates.length === 0) {
      panel.classList.remove('open');
      return;
    }
    var title = document.createElement('div');
    title.className = 'choices-title';
    title.textContent = 'Ambiguous "' + d.query + '" — pick one:';
    panel.appendChild(title);
    d.candidates.forEach(function (c) {
      var item = document.createElement('button');
      item.className = 'choice';
      item.textContent = c.method + ' /' + c.path + (c.action ? '  →  ' + c.action : '');
      item.addEventListener('click', function () {
        send('setRoot', { query: c.method + ' /' + c.path });
        panel.classList.remove('open');
      });
      panel.appendChild(item);
    });
    panel.classList.add('open');
  }

  // ---- live stream --------------------------------------------------------

  function connect() {
    var es = new EventSource(withToken('/events'));
    es.addEventListener('graph:update', function (e) {
      ingest(JSON.parse(e.data));
    });
    es.addEventListener('compare:update', function (e) {
      ingestCompare(JSON.parse(e.data));
    });
    es.addEventListener('focus:update', function (e) {
      try {
        applyFocus(JSON.parse(e.data));
      } catch (_) {
        /* ignore */
      }
    });
    es.addEventListener('choices', function (e) {
      try {
        showChoices(JSON.parse(e.data));
      } catch (_) {
        /* ignore */
      }
    });
    es.addEventListener('status', function (e) {
      try {
        var d = JSON.parse(e.data);
        if (d.message) setStatus(d.message);
        else if (d.connected) setStatus('connected');
      } catch (_) {
        setStatus(e.data);
      }
    });
    es.onerror = function () {
      setStatus('reconnecting…');
    };
  }

  // ---- bootstrap ----------------------------------------------------------

  // Load only the scripts the chosen renderer needs (the 3D bundle and the 2D
  // Cytoscape stack are each heavy; never pay for both).
  function loadScripts(srcs, done) {
    (function next(i) {
      if (i >= srcs.length) return done();
      var s = document.createElement('script');
      s.src = srcs[i];
      s.onload = function () {
        next(i + 1);
      };
      s.onerror = function () {
        setStatus('failed to load ' + srcs[i]);
      };
      document.body.appendChild(s);
    })(0);
  }

  function init() {
    var ctx = {
      container: document.getElementById('cy'),
      theme: resolvedTheme,
      layout: layout,
      layerOrder: LAYER_ORDER,
      onNodeClick: function (id) {
        send('reveal', { nodeId: id });
        send('expand', { nodeId: id });
        send('focus', { nodeId: id });
      },
      onClearFocus: function () {
        send('clearFocus');
      },
      onNodeHover: showDetail,
      colorForNode: colorForNode,
      labelFor: labelFor,
    };
    view = renderer === '2d' ? window.createCyRenderer(ctx) : window.createForceRenderer(ctx);

    document.getElementById('fit').addEventListener('click', function () {
      view.fit();
    });
    document.getElementById('relayout').addEventListener('click', function () {
      view.relayout();
    });
    document.getElementById('search').addEventListener('input', function (e) {
      view.search(e.target.value.trim().toLowerCase());
    });
    document.getElementById('pathfilter').addEventListener('input', function (e) {
      pathFilters = e.target.value
        .toLowerCase()
        .split(',')
        .map(function (s) {
          return s.trim();
        })
        .filter(Boolean);
      applyActiveFilters();
    });

    // Labels toggle: only meaningful where the renderer can draw them (3D). The
    // 2D renderer always labels, so hide the control there.
    var labelsBtn = document.getElementById('labels');
    if (view.setLabels) {
      labelsBtn.addEventListener('click', function () {
        var on = labelsBtn.getAttribute('aria-pressed') !== 'true';
        labelsBtn.setAttribute('aria-pressed', String(on));
        view.setLabels(on);
      });
    } else {
      labelsBtn.style.display = 'none';
    }

    connect();
  }

  // Bring up THREE + SpriteText as globals (for 3D sprite labels) before the
  // force-graph bundle, so the UMD bundle and SpriteText share one three. If the
  // module load fails for any reason, fall back to loading the bundle alone —
  // the 3D view then works exactly as before, just without always-on labels.
  function load3d(done) {
    var bundle = ['/vendor/3d-force-graph.min.js', '/renderer_3d.js'];
    var started = false;
    function go() {
      if (started) return;
      started = true;
      loadScripts(bundle, done);
    }
    try {
      var im = document.createElement('script');
      im.type = 'importmap';
      im.textContent = JSON.stringify({ imports: { three: '/vendor/three.module.min.js' } });
      document.head.appendChild(im);
      var boot = document.createElement('script');
      boot.type = 'module';
      boot.textContent =
        "import * as THREE from 'three';" +
        "import SpriteText from '/vendor/three-spritetext.module.js';" +
        'window.THREE = THREE; window.SpriteText = SpriteText;' +
        "window.dispatchEvent(new Event('cartograph:labels-ready'));";
      window.addEventListener('cartograph:labels-ready', go);
      document.head.appendChild(boot);
      // Safety net: proceed without sprite labels if the module never resolves.
      setTimeout(go, 4000);
    } catch (e) {
      go();
    }
  }

  document.body.setAttribute('data-theme', theme);
  document.body.setAttribute('data-renderer', renderer);
  if (renderer === '2d') {
    loadScripts(['/vendor/cytoscape.min.js', '/vendor/dagre.min.js', '/vendor/cytoscape-dagre.min.js', '/renderer_cy.js'], init);
  } else {
    load3d(init);
  }
})();
