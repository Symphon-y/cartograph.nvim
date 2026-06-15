/* cartograph 2D renderer — Cytoscape + dagre.
 *
 * The original force/DAG view, factored behind the shared renderer interface so
 * app.js can swap it for the 3D renderer. The factory receives a `ctx`:
 *   { container, theme, onNodeClick(id), colorForNode(data) }
 * and returns { merge, renderCompare, search, applyFilters, fit, relayout }.
 */
window.createCyRenderer = function (ctx) {
  'use strict';

  var cy = cytoscape({
    container: ctx.container,
    wheelSensitivity: 0.2,
    style: [
      {
        selector: 'node',
        style: {
          'background-color': function (ele) {
            return ctx.colorForNode(ele.data());
          },
          label: 'data(label)',
          color: 'var(--text)',
          'font-size': 11,
          'text-valign': 'bottom',
          'text-margin-y': 4,
          width: 18,
          height: 18,
          'border-width': 2,
          'border-color': '#00000022',
        },
      },
      { selector: 'node.expanded', style: { 'border-color': 'var(--accent)', 'border-width': 3 } },
      {
        selector: 'edge',
        style: {
          width: 1.5,
          'line-color': '#94a3b8',
          'target-arrow-color': '#94a3b8',
          'target-arrow-shape': 'triangle',
          'curve-style': 'bezier',
          label: 'data(kind)',
          'font-size': 8,
          color: '#94a3b8',
          'text-rotation': 'autorotate',
        },
      },
      { selector: '.faded', style: { opacity: 0.15 } },
      { selector: '.match', style: { 'border-color': '#facc15', 'border-width': 4 } },
      { selector: '.hidden', style: { display: 'none' } },
      // Focus/trace overlay: dim everything off the focus set; accent the path.
      { selector: '.unfocused', style: { opacity: 0.12 } },
      { selector: 'node.onpath', style: { 'border-color': '#fbbf24', 'border-width': 4 } },
      {
        selector: 'edge.onpath',
        style: { 'line-color': '#fbbf24', 'target-arrow-color': '#fbbf24', width: 3, opacity: 1 },
      },
      // Compare overlay: shared solid green; each side dashed in its colour.
      { selector: 'node.side-both', style: { 'border-color': '#22c55e', 'border-width': 4 } },
      { selector: 'node.side-a', style: { 'border-color': '#3b82f6', 'border-width': 3, 'border-style': 'dashed' } },
      { selector: 'node.side-b', style: { 'border-color': '#f59e0b', 'border-width': 3, 'border-style': 'dashed' } },
      { selector: 'edge.side-both', style: { 'line-color': '#22c55e', 'target-arrow-color': '#22c55e' } },
      { selector: 'edge.side-a', style: { 'line-color': '#3b82f6', 'target-arrow-color': '#3b82f6', 'line-style': 'dashed' } },
      { selector: 'edge.side-b', style: { 'line-color': '#f59e0b', 'target-arrow-color': '#f59e0b', 'line-style': 'dashed' } },
    ],
  });

  var layoutName = ctx.layout || 'dagre';

  function relayout() {
    var opts = { name: layoutName, animate: true, animationDuration: 200 };
    if (layoutName === 'dagre') {
      opts.rankDir = 'LR';
      opts.nodeSep = 30;
      opts.rankSep = 60;
    }
    cy.layout(opts).run();
  }

  cy.on('tap', 'node', function (evt) {
    evt.target.addClass('expanded');
    ctx.onNodeClick(evt.target.id());
  });

  if (ctx.onNodeHover) {
    cy.on('mouseover', 'node', function (evt) {
      ctx.onNodeHover(evt.target.data());
    });
    cy.on('mouseout', 'node', function () {
      ctx.onNodeHover(null);
    });
  }

  // Clicking empty canvas clears the focus/trace path.
  cy.on('tap', function (evt) {
    if (evt.target === cy && ctx.onClearFocus) ctx.onClearFocus();
  });

  function nodeData(n) {
    return {
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
  }

  function merge(graph) {
    var added = 0;
    (graph.nodes || []).forEach(function (n) {
      var existing = cy.getElementById(n.id);
      if (existing.empty()) {
        cy.add({ group: 'nodes', data: nodeData(n) });
        added++;
      } else if (n.layer) {
        existing.data('layer', n.layer); // fill in a newly known layer
      }
    });
    (graph.edges || []).forEach(function (e) {
      var id = e.from + '__' + e.kind + '__' + e.to;
      if (cy.getElementById(id).empty() && !cy.getElementById(e.from).empty() && !cy.getElementById(e.to).empty()) {
        cy.add({ group: 'edges', data: { id: id, source: e.from, target: e.to, kind: e.kind } });
        added++;
      }
    });
    if (added > 0) relayout();
  }

  function renderCompare(diff) {
    cy.elements().remove();
    (diff.nodes || []).forEach(function (n) {
      cy.add({ group: 'nodes', data: nodeData(n), classes: 'side-' + n.side });
    });
    (diff.edges || []).forEach(function (e) {
      var id = e.from + '__' + e.kind + '__' + e.to;
      if (!cy.getElementById(e.from).empty() && !cy.getElementById(e.to).empty()) {
        cy.add({ group: 'edges', data: { id: id, source: e.from, target: e.to, kind: e.kind }, classes: 'side-' + e.side });
      }
    });
    relayout();
  }

  function search(q) {
    cy.elements().removeClass('faded match');
    if (!q) return;
    var matches = cy.nodes().filter(function (n) {
      return (n.data('label') || '').toLowerCase().indexOf(q) !== -1;
    });
    if (matches.nonempty()) {
      cy.elements().addClass('faded');
      matches.removeClass('faded').addClass('match');
      cy.animate({ fit: { eles: matches, padding: 60 }, duration: 200 });
    }
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
    cy.nodes().forEach(function (n) {
      var okL = !f.layers || f.layers[n.data('layer') || 'unknown'];
      var okK = !f.kinds || f.kinds[n.data('kind')];
      var okP = !hiddenByPath(n.data('file'), f.paths);
      n.toggleClass('hidden', !(okL && okK && okP));
    });
  }

  // Apply the focus/trace overlay (see renderer_3d.applyFocus). Empty path
  // clears focus. Uses dedicated classes so it composes with search's `.faded`.
  function applyFocus(overlay) {
    var path = (overlay && overlay.path) || [];
    cy.elements().removeClass('unfocused onpath');
    if (!path.length) return;
    var active = overlay.active || {};
    var pathEdges = {};
    for (var i = 0; i < path.length - 1; i++) {
      pathEdges[path[i].id + '__' + path[i + 1].id] = true;
    }
    cy.nodes().forEach(function (n) {
      n.toggleClass('unfocused', !active[n.id()]);
    });
    cy.edges().forEach(function (e) {
      var s = e.source().id();
      var t = e.target().id();
      var on = active[s] && active[t];
      e.toggleClass('unfocused', !on);
      if (on && pathEdges[s + '__' + t]) e.addClass('onpath');
    });
    var nodes = cy.collection();
    path.forEach(function (p) {
      var el = cy.getElementById(p.id);
      if (el.nonempty()) nodes = nodes.union(el);
    });
    if (nodes.nonempty()) cy.animate({ fit: { eles: nodes, padding: 80 }, duration: 250 });
  }

  function fit() {
    cy.fit(undefined, 40);
  }

  return {
    merge: merge,
    renderCompare: renderCompare,
    search: search,
    applyFilters: applyFilters,
    applyFocus: applyFocus,
    fit: fit,
    relayout: relayout,
  };
};
