/* cartograph 3D renderer — force-directed graph via 3d-force-graph (Three.js +
 * d3-force-3d, vendored standalone). Implements the same renderer interface as
 * renderer_cy.js so app.js can swap them by the `?renderer` param.
 *
 * CLEAN layers are made spatial: a custom positioning force pulls each node to a
 * horizontal plane chosen by its layer, so the architecture reads top-to-bottom.
 *
 * ctx: { container, theme, layerOrder, planeGap, onNodeClick(id), colorForNode(data) }
 */
window.createForceRenderer = function (ctx) {
  'use strict';

  var bg = ctx.theme === 'light' ? '#ffffff' : '#0b1020';
  var planeGap = ctx.planeGap || 80;

  // Stable Y for a layer: centre the configured layer order around 0, top-down.
  function planeFor(layer) {
    var order = ctx.layerOrder;
    var idx = order.indexOf(layer || 'unknown');
    if (idx === -1) idx = order.length; // unseen layers sink to the bottom
    var mid = (order.length - 1) / 2;
    return (mid - idx) * planeGap;
  }

  var data = { nodes: [], links: [] };
  var nodeById = {};
  var linkSeen = {};

  // Focus/trace overlay state: a set of "active" node ids (null = no focus), and
  // the set of on-path edges ("from__to" for consecutive breadcrumb nodes).
  var focusActive = null;
  var pathEdges = {};
  var PATH_COLOR = '#fbbf24';

  function endpointId(end) {
    return typeof end === 'object' ? end.id : end;
  }

  function nodeColor(n) {
    if (n.__dim || (focusActive && !focusActive[n.id])) return '#33415577';
    return ctx.colorForNode(n);
  }
  function linkColor(l) {
    if (focusActive) {
      var s = endpointId(l.source);
      var t = endpointId(l.target);
      if (!(focusActive[s] && focusActive[t])) return '#3341551f';
      if (pathEdges[s + '__' + t]) return PATH_COLOR;
    }
    return l.__dim ? '#3341553a' : '#94a3b8';
  }

  var Graph = ForceGraph3D()(ctx.container)
    .backgroundColor(bg)
    .nodeRelSize(4)
    .nodeLabel(function (n) {
      return (n.kind ? n.kind + '  ·  ' : '') + (n.name || n.label || '');
    })
    .nodeColor(nodeColor)
    .nodeVisibility(function (n) {
      return !n.__hidden;
    })
    .linkColor(linkColor)
    .linkVisibility(function (l) {
      var s = typeof l.source === 'object' ? l.source : nodeById[l.source];
      var t = typeof l.target === 'object' ? l.target : nodeById[l.target];
      return !(s && s.__hidden) && !(t && t.__hidden);
    })
    .linkDirectionalArrowLength(3)
    .linkDirectionalArrowRelPos(1)
    .linkOpacity(0.5)
    .onNodeClick(function (n) {
      ctx.onNodeClick(n.id);
      aimAt(n);
    })
    .onNodeHover(function (n) {
      if (ctx.onNodeHover) ctx.onNodeHover(n || null);
    })
    .onBackgroundClick(function () {
      if (ctx.onClearFocus) ctx.onClearFocus();
    });

  // Always-on text labels via three-spritetext (loaded as a global before the
  // bundle). Degrades to hover-only when SpriteText is unavailable. Suppressed
  // past a node cap so dense repo graphs stay legible and fast.
  var labelsEnabled = true;
  var LABEL_CAP = 400;
  function makeLabel(n) {
    if (!labelsEnabled || typeof window.SpriteText === 'undefined') return null;
    if (data.nodes.length > LABEL_CAP) return null;
    var t = new window.SpriteText(n.name || n.label || '');
    t.color = ctx.theme === 'light' ? '#1f2937' : '#e2e8f0';
    t.textHeight = 3;
    t.fontFace = 'ui-sans-serif, system-ui, sans-serif';
    t.position.set(0, 7, 0);
    if (t.material) t.material.depthWrite = false;
    return t;
  }
  Graph.nodeThreeObjectExtend(true).nodeThreeObject(makeLabel);

  function setLabels(on) {
    labelsEnabled = on;
    Graph.nodeThreeObject(makeLabel); // re-evaluate per-node objects
  }

  // Custom layer force: nudge each node toward its layer's plane every tick.
  function layerForce(strength) {
    var nodes;
    function force(alpha) {
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        n.vy += (planeFor(n.layer) - n.y) * strength * alpha;
      }
    }
    force.initialize = function (n) {
      nodes = n;
    };
    return force;
  }
  Graph.d3Force('layer', layerForce(0.35));
  if (Graph.d3Force('charge')) Graph.d3Force('charge').strength(-45);

  function refreshStyles() {
    Graph.nodeColor(nodeColor).linkColor(linkColor);
  }
  function refreshVisibility() {
    Graph.nodeVisibility(Graph.nodeVisibility()).linkVisibility(Graph.linkVisibility());
  }

  function aimAt(n) {
    if (typeof n.x !== 'number') return;
    var d = 90;
    var len = Math.hypot(n.x, n.y, n.z) || 1;
    var r = 1 + d / len;
    Graph.cameraPosition({ x: n.x * r, y: n.y * r, z: n.z * r }, n, 700);
  }

  function addNode(n) {
    if (nodeById[n.id]) {
      if (n.layer) nodeById[n.id].layer = n.layer;
      return false;
    }
    var obj = {
      id: n.id,
      name: n.name,
      label: ctx.labelFor ? ctx.labelFor(n) : n.name,
      kind: n.kind,
      file: n.file,
      layer: n.layer,
      side: n.side,
      lang: n.lang,
      snippet: n.meta && n.meta.snippet,
      line: n.range && n.range.start ? n.range.start.line : null,
    };
    nodeById[n.id] = obj;
    data.nodes.push(obj);
    return true;
  }
  function addLink(e) {
    var id = e.from + '__' + e.kind + '__' + e.to;
    if (linkSeen[id] || !nodeById[e.from] || !nodeById[e.to]) return false;
    linkSeen[id] = true;
    data.links.push({ source: e.from, target: e.to, kind: e.kind, side: e.side });
    return true;
  }

  function merge(graph) {
    var added = 0;
    (graph.nodes || []).forEach(function (n) {
      if (addNode(n)) added++;
    });
    (graph.edges || []).forEach(function (e) {
      if (addLink(e)) added++;
    });
    if (added > 0) Graph.graphData(data);
  }

  function renderCompare(diff) {
    data = { nodes: [], links: [] };
    nodeById = {};
    linkSeen = {};
    (diff.nodes || []).forEach(addNode);
    (diff.edges || []).forEach(addLink);
    Graph.graphData(data);
  }

  function search(q) {
    var match = null;
    data.nodes.forEach(function (n) {
      var hit = q && (n.name || n.label || '').toLowerCase().indexOf(q) !== -1;
      n.__dim = q ? !hit : false;
      if (hit) match = n;
    });
    data.links.forEach(function (l) {
      l.__dim = !!q;
    });
    refreshStyles();
    if (match) aimAt(match);
  }

  function hiddenByPath(file, paths) {
    if (!paths || !paths.length || !file) return false;
    var lower = file.toLowerCase();
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] && lower.indexOf(paths[i]) !== -1) return true;
    }
    return false;
  }

  function applyFilters(f) {
    data.nodes.forEach(function (n) {
      var okL = !f.layers || f.layers[n.layer || 'unknown'];
      var okK = !f.kinds || f.kinds[n.kind];
      var okP = !hiddenByPath(n.file, f.paths);
      n.__hidden = !(okL && okK && okP);
    });
    refreshVisibility();
  }

  // Apply the focus/trace overlay: { active: {id->true}, path: [{id,…}] }. An
  // empty path clears focus and un-dims the graph. Composes with search (__dim)
  // and filters (__hidden) since each owns a separate flag.
  function applyFocus(overlay) {
    var path = (overlay && overlay.path) || [];
    if (!path.length) {
      focusActive = null;
      pathEdges = {};
      refreshStyles();
      return;
    }
    focusActive = overlay.active || {};
    pathEdges = {};
    for (var i = 0; i < path.length - 1; i++) {
      pathEdges[path[i].id + '__' + path[i + 1].id] = true;
    }
    refreshStyles();
    var tail = overlay.tail && nodeById[overlay.tail];
    if (tail) aimAt(tail);
  }

  function fit() {
    Graph.zoomToFit(500, 40);
  }
  function relayout() {
    Graph.d3ReheatSimulation();
  }

  // Keep the canvas sized to its container.
  window.addEventListener('resize', function () {
    Graph.width(ctx.container.clientWidth).height(ctx.container.clientHeight);
  });
  Graph.width(ctx.container.clientWidth).height(ctx.container.clientHeight);

  return {
    merge: merge,
    renderCompare: renderCompare,
    search: search,
    applyFilters: applyFilters,
    applyFocus: applyFocus,
    setLabels: setLabels,
    fit: fit,
    relayout: relayout,
  };
};
