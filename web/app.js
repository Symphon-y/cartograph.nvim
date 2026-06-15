/* cartograph web UI — a live, two-way view of the engine's graph.
 *
 * Neovim is the brain: it pushes graph updates over SSE; clicking a node POSTs
 * an action back (expand the next hop, reveal in the editor). The browser only
 * renders and forwards intent — no graph logic lives here.
 */
(function () {
  'use strict';

  var params = new URLSearchParams(window.location.search);
  var token = params.get('token') || '';
  var theme = params.get('theme') || 'auto';
  var layoutName = params.get('layout') || 'dagre';

  // Colour per node kind. One source of truth, shared by Cytoscape + legend.
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

  // ---- transport ----------------------------------------------------------

  function withToken(path) {
    return path + (path.indexOf('?') === -1 ? '?' : '&') + 'token=' + encodeURIComponent(token);
  }

  // POST a browser->nvim action. Body matches cartograph.protocol's contract.
  function send(action, params) {
    var body = Object.assign({ action: action }, params || {});
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

  // ---- rendering ----------------------------------------------------------

  var cy = cytoscape({
    container: document.getElementById('cy'),
    wheelSensitivity: 0.2,
    style: [
      {
        selector: 'node',
        style: {
          'background-color': function (ele) {
            return KIND_COLOR[ele.data('kind')] || KIND_COLOR.call;
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
      {
        selector: 'node.expanded',
        style: { 'border-color': 'var(--accent)', 'border-width': 3 },
      },
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
      // Compare overlay: shared nodes are solid green; each side's unique nodes
      // are dashed in that side's colour.
      { selector: 'node.side-both', style: { 'border-color': '#22c55e', 'border-width': 4, 'border-style': 'solid' } },
      { selector: 'node.side-a', style: { 'border-color': '#3b82f6', 'border-width': 3, 'border-style': 'dashed' } },
      { selector: 'node.side-b', style: { 'border-color': '#f59e0b', 'border-width': 3, 'border-style': 'dashed' } },
      { selector: 'edge.side-both', style: { 'line-color': '#22c55e', 'target-arrow-color': '#22c55e' } },
      { selector: 'edge.side-a', style: { 'line-color': '#3b82f6', 'target-arrow-color': '#3b82f6', 'line-style': 'dashed' } },
      { selector: 'edge.side-b', style: { 'line-color': '#f59e0b', 'target-arrow-color': '#f59e0b', 'line-style': 'dashed' } },
    ],
  });

  function layout() {
    var opts = { name: layoutName, animate: true, animationDuration: 200 };
    if (layoutName === 'dagre') {
      opts.rankDir = 'LR';
      opts.nodeSep = 30;
      opts.rankSep = 60;
    }
    cy.layout(opts).run();
  }

  // Merge a serialized graph ({ nodes, edges }) into the view. New elements are
  // added and the layout re-runs only when something actually changed, so the
  // user's pan/zoom survives incremental expansion.
  function merge(graph) {
    if (!graph) return;
    var added = 0;
    (graph.nodes || []).forEach(function (n) {
      if (cy.getElementById(n.id).empty()) {
        cy.add({ group: 'nodes', data: { id: n.id, label: n.name, kind: n.kind, file: n.file } });
        added++;
      }
    });
    (graph.edges || []).forEach(function (e) {
      var id = e.from + '__' + e.kind + '__' + e.to;
      if (cy.getElementById(id).empty() && !cy.getElementById(e.from).empty() && !cy.getElementById(e.to).empty()) {
        cy.add({ group: 'edges', data: { id: id, source: e.from, target: e.to, kind: e.kind } });
        added++;
      }
    });
    if (added > 0) {
      layout();
    }
  }

  // Replace the view with a compare overlay ({ nodes, edges, summary }), where
  // each element carries a `side` of 'a' | 'b' | 'both'.
  function renderCompare(diff) {
    cy.elements().remove();
    (diff.nodes || []).forEach(function (n) {
      cy.add({ group: 'nodes', data: { id: n.id, label: n.name, kind: n.kind, file: n.file }, classes: 'side-' + n.side });
    });
    (diff.edges || []).forEach(function (e) {
      var id = e.from + '__' + e.kind + '__' + e.to;
      if (!cy.getElementById(e.from).empty() && !cy.getElementById(e.to).empty()) {
        cy.add({ group: 'edges', data: { id: id, source: e.from, target: e.to, kind: e.kind }, classes: 'side-' + e.side });
      }
    });
    layout();
    var s = diff.summary || {};
    setStatus('compare: ' + (s.shared || 0) + ' shared · ' + (s.only_a || 0) + ' only-A · ' + (s.only_b || 0) + ' only-B');
  }

  // ---- interactions -------------------------------------------------------

  // Click a node: drill the next hop (expand) and follow it in the editor.
  cy.on('tap', 'node', function (evt) {
    var id = evt.target.id();
    evt.target.addClass('expanded');
    send('reveal', { nodeId: id });
    send('expand', { nodeId: id });
  });

  document.getElementById('fit').addEventListener('click', function () {
    cy.fit(undefined, 40);
  });
  document.getElementById('relayout').addEventListener('click', layout);

  document.getElementById('search').addEventListener('input', function (e) {
    var q = e.target.value.trim().toLowerCase();
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
  });

  // ---- ambiguity pick-list ------------------------------------------------

  // Render an interactive pick-list when a query matched several endpoints.
  // Choosing one re-roots on that exact method+path to disambiguate.
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

  // ---- theme + legend -----------------------------------------------------

  function buildLegend() {
    var el = document.getElementById('legend');
    el.innerHTML = '';
    Object.keys(KIND_COLOR).forEach(function (kind) {
      var s = document.createElement('span');
      s.className = 'swatch';
      s.innerHTML = '<span class="dot" style="background:' + KIND_COLOR[kind] + '"></span>' + kind;
      el.appendChild(s);
    });
  }

  // ---- live stream --------------------------------------------------------

  function connect() {
    var es = new EventSource(withToken('/events'));
    es.addEventListener('graph:update', function (e) {
      merge(JSON.parse(e.data));
    });
    es.addEventListener('compare:update', function (e) {
      renderCompare(JSON.parse(e.data));
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

  document.body.setAttribute('data-theme', theme);
  buildLegend();
  connect();
})();
