// App: owns all state — agents (as Herdr would report), notch mode, simulation, tweaks.

const { useState, useEffect, useRef, useLayoutEffect, useCallback } = React;

const SCREEN_W = 1280;
const SCREEN_H = 720;
const EXPANDED_W = { overview: 400, approval: 400, question: 372, unknown: 372, feedback: 270 };

const EXTRA_AGENTS = [
  { id: 'work:w2:p1', session: 'work', agent: 'codex', project: 'payments', title: 'Migrate Stripe webhooks', status: 'working', since: Date.now() - 9 * 60000, interaction: null },
  { id: 'work:w2:p2', session: 'work', agent: 'claude', project: 'docs-site', title: 'Rewrite onboarding guide', status: 'idle', since: Date.now() - 180 * 60000, interaction: null },
  { id: 'default:w3:p1', session: 'default', agent: 'opencode', project: 'cli', title: 'Add --json output flag', status: 'working', since: Date.now() - 4 * 60000, interaction: null },
];

const AUTOPLAY = [
  { id: 'default:w1:p1', to: 'blocked', i: 'claudeEdit' },
  { id: 'default:w2:p1', to: 'blocked', i: 'codexCommand' },
  { id: 'default:w2:p3', to: 'working' },
  { id: 'default:w2:p3', to: 'blocked', i: 'claudeAsk' },
  { id: 'work:w1:p2', to: 'blocked', i: 'unknown' },
];

function useClock() {
  const [t, setT] = useState(new Date());
  useEffect(() => { const h = setInterval(() => setT(new Date()), 15000); return () => clearInterval(h); }, []);
  return t.toLocaleString('en-US', { weekday: 'short', hour: 'numeric', minute: '2-digit' });
}

function useScale(reserve) {
  const [s, setS] = useState(1);
  useEffect(() => {
    const fit = () => setS(Math.min(1, (window.innerWidth - 48 - reserve) / SCREEN_W, (window.innerHeight - 170) / SCREEN_H));
    fit(); window.addEventListener('resize', fit); return () => window.removeEventListener('resize', fit);
  }, [reserve]);
  return s;
}

function App() {
  const [agents, setAgents] = useState(initialAgents);
  const [mode, setMode] = useState('compact');        // compact | overview | interaction | feedback
  const [selectedId, setSelectedId] = useState(null);
  const [pinned, setPinned] = useState(false);
  const [autoOpened, setAutoOpened] = useState(false);
  const [engaged, setEngaged] = useState(false);
  const [sending, setSending] = useState(null);
  const [notice, setNotice] = useState('');
  const [feedback, setFeedback] = useState({ text: '', color: '' });
  const [focusedId, setFocusedId] = useState('default:w1:p1');
  const [flash, setFlash] = useState(false);
  const [raised, setRaised] = useState(false);
  const [contentH, setContentH] = useState(0);
  const [showTweaks, setShowTweaks] = useState(true);
  const [tw, setTw] = useState({
    variant: 'B', density: 'hero', autoExpand: true, autoplay: true, count: 'normal', offline: false, nextStale: false,
  });
  const clock = useClock();
  const scale = useScale(showTweaks ? 324 : 0);
  const hoverTimer = useRef(null);
  const layerRef = useRef(null);
  const step = useRef(0);
  const [, force] = useState(0);

  const selected = agents.find((a) => a.id === selectedId);
  const multiSession = new Set(agents.map((a) => a.session)).size > 1;
  const setTweak = (k, v) => setTw((p) => ({ ...p, [k]: v }));

  // Durations tick
  useEffect(() => { const h = setInterval(() => force((x) => x + 1), 30000); return () => clearInterval(h); }, []);

  // Agent count tweak
  useEffect(() => {
    setAgents((prev) => {
      const base = prev.filter((a) => !EXTRA_AGENTS.some((e) => e.id === a.id));
      if (tw.count === 'one') return base.slice(0, 1);
      if (tw.count === 'many') return [...(base.length < 4 ? initialAgents() : base), ...EXTRA_AGENTS];
      return base.length < 4 ? initialAgents() : base;
    });
  }, [tw.count]);

  const update = useCallback((id, patch) => {
    setAgents((prev) => prev.map((a) => (a.id === id ? { ...a, since: Date.now(), ...patch } : a)));
  }, []);

  // A Herdr state change arrives
  const applyChange = useCallback((id, to, ikey) => {
    setAgents((prev) => {
      const a = prev.find((x) => x.id === id);
      if (!a || a.status === to) return prev;
      return prev.map((x) => (x.id === id
        ? { ...x, status: to, since: Date.now(), interaction: to === 'blocked' ? INTERACTIONS[ikey] : null }
        : x));
    });
    if (to === 'blocked') {
      setMode((m) => {
        if (m === 'compact' && tw.autoExpand) {
          setSelectedId(id); setAutoOpened(true); setEngaged(false); setNotice('');
          return 'interaction';
        }
        return m;
      });
    }
  }, [tw.autoExpand]);

  // Autoplay script
  useEffect(() => {
    if (!tw.autoplay || tw.offline) return;
    const h = setInterval(() => {
      const s = AUTOPLAY[step.current % AUTOPLAY.length];
      step.current += 1;
      applyChange(s.id, s.to, s.i);
    }, 9000);
    return () => clearInterval(h);
  }, [tw.autoplay, tw.offline, applyChange]);

  // Auto-opened card collapses after 8s without engagement
  useEffect(() => {
    if (mode !== 'interaction' || !autoOpened || engaged) return;
    const h = setTimeout(() => { setMode('compact'); setAutoOpened(false); }, 8000);
    return () => clearTimeout(h);
  }, [mode, autoOpened, engaged, selectedId]);

  // If the selected prompt resolves elsewhere, close the card
  useEffect(() => {
    if (mode === 'interaction' && selected && selected.status !== 'blocked' && !sending) {
      showFeedback('Resolved in Herdr', '#a3a3a3');
    }
  }, [selected?.status]);

  // Measure the active layer for the notch height
  useLayoutEffect(() => {
    const el = layerRef.current;
    if (!el) { setContentH(0); return; }
    const ro = new ResizeObserver(() => setContentH(el.offsetHeight));
    ro.observe(el); setContentH(el.offsetHeight);
    return () => ro.disconnect();
  }, [mode, selectedId, tw.density, agents.length, notice, tw.offline]);

  function showFeedback(text, color) {
    setFeedback({ text, color }); setMode('feedback'); setSending(null);
    setTimeout(() => {
      setMode((m) => (m === 'feedback' ? (pinned ? 'overview' : 'compact') : m));
      setAutoOpened(false);
    }, 900);
  }

  function jump(a) {
    setFocusedId(a.id); setRaised(true); setFlash(true);
    setTimeout(() => setFlash(false), 700);
    if (a.status === 'done') update(a.id, { status: 'idle' });
    setMode('compact'); setPinned(false);
  }

  function openRow(a) {
    setEngaged(true);
    if (a.status === 'blocked') { setSelectedId(a.id); setNotice(''); setMode('interaction'); setAutoOpened(false); }
    else jump(a);
  }

  function respond(choice, text) {
    if (!selected || sending !== null) return;
    setEngaged(true);
    // Revalidation: status/state_change_seq/fingerprint must match before any key is sent.
    if (tw.nextStale) {
      setTweak('nextStale', false);
      const i = selected.interaction;
      const changed = i.kind === 'approval' && i.diff
        ? { ...i, target: 'src/auth/session.ts', diff: i.diff.map((d) => ({ ...d, s: d.s.replace('jwt', 'session') })) }
        : { ...i, question: i.question.replace('?', ' (updated)?') };
      update(selected.id, { interaction: changed, status: 'blocked' });
      setNotice('This prompt changed. Nothing was sent.');
      return;
    }
    setSending(choice); setNotice('');
    const isDeny = choice === 'deny' || (selected.interaction.kind === 'approval' && choice === 2);
    setTimeout(() => {
      const id = selected.id;
      update(id, { status: 'working', interaction: null });
      setTimeout(() => update(id, { status: 'done' }), 6000);
      const kind = selected.interaction.kind;
      showFeedback(isDeny ? 'Denied' : kind === 'question' ? (text ? 'Answer sent' : 'Answered') : 'Approved',
        isDeny ? '#fca5a5' : 'var(--vi-idle)');
    }, 650);
  }

  // Keyboard — only while an interaction card is visible
  useEffect(() => {
    const onKey = (e) => {
      if (mode !== 'interaction' || !selected || selected.status !== 'blocked') return;
      if (e.target.tagName === 'INPUT') { if (e.key === 'Escape') e.target.blur(); return; }
      const i = selected.interaction;
      if (e.key === 'Escape') { i.kind === 'approval' ? respond('deny') : setMode('overview'); }
      else if (e.key === 'Enter' && i.kind !== 'unknown') respond(0);
      else if (/^[1-9]$/.test(e.key) && i.choices && +e.key <= i.choices.length) respond(+e.key - 1);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  // Hover intent
  function onEnter() {
    clearTimeout(hoverTimer.current);
    hoverTimer.current = setTimeout(() => setMode((m) => (m === 'compact' ? 'overview' : m)), 120);
    if (mode === 'interaction') setEngaged(true);
  }
  function onLeave() {
    clearTimeout(hoverTimer.current);
    if (pinned) return;
    hoverTimer.current = setTimeout(() => setMode((m) => (m === 'overview' ? 'compact' : m)), 280);
  }
  function onBandClick() {
    if (mode === 'compact' || (mode === 'overview' && !pinned)) { setMode('overview'); setPinned(true); }
    else { setMode('compact'); setPinned(false); }
  }
  function onScreenClick(e) {
    if (e.target.closest('.notch')) return;
    setMode('compact'); setPinned(false); setRaised(false);
  }

  // Geometry
  const wing = wingWidth(tw.variant, agents);
  const compactW = PHYS_W + wing * 2;
  const ikind = selected?.interaction?.kind;
  const layerKey = mode === 'interaction' && selected?.status === 'blocked' ? (ikind || 'unknown') : mode;
  const width = mode === 'compact' ? compactW : Math.max(compactW, EXPANDED_W[layerKey] || 400);
  const height = mode === 'compact' ? BAND_H : BAND_H + contentH;
  const radius = mode === 'compact' ? 10 : 18;
  const bandWing = (width - PHYS_W) / 2;

  let layer = null;
  if (mode === 'overview') {
    layer = <Overview agents={agents} density={tw.density} multiSession={multiSession} offline={tw.offline} onRow={openRow}></Overview>;
  } else if (mode === 'interaction' && selected && selected.status === 'blocked') {
    const common = { a: selected, onBack: () => { setMode('overview'); setPinned(true); }, onOpen: () => jump(selected), sending, notice };
    layer = ikind === 'approval' ? <ApprovalCard {...common} onChoose={(c) => respond(c)}></ApprovalCard>
      : ikind === 'question' ? <AskCard key={selected.interaction.question} {...common} onChoose={(c) => respond(c)} onText={(t) => respond('text', t)}></AskCard>
      : <FallbackCard {...common}></FallbackCard>;
  } else if (mode === 'feedback') {
    layer = <Feedback text={feedback.text} color={feedback.color}></Feedback>;
  }

  const blockedCount = agents.filter((a) => a.status === 'blocked').length;

  return (
    <div className={`page ${showTweaks ? 'has-tweaks' : ''}`}>
      <div className="stage" style={{ width: SCREEN_W * scale, height: SCREEN_H * scale }}>
        <div className="screen" data-screen-label="MacBook screen" style={{ transform: `scale(${scale})` }} onMouseDown={onScreenClick}>
          <MenuBar clock={clock}></MenuBar>
          <div className="desktop">
            <HerdrWindow agents={agents} focusedId={focusedId} flash={flash} raised={raised}></HerdrWindow>
          </div>
          <div className="notch-wrap">
            <div className={`notch notch-${mode} ${blockedCount && mode === 'compact' ? 'notch-alert' : ''}`}
              style={{ width, height, borderRadius: `0 0 ${radius}px ${radius}px` }}
              onMouseEnter={onEnter} onMouseLeave={onLeave} data-screen-label={`Notch ${mode}`}>
              <div onClick={onBandClick}>
                <TopBand variant={tw.variant} agents={agents} offline={tw.offline} wing={bandWing}></TopBand>
              </div>
              <div className="layer-host" key={`${layerKey}-${selectedId}`}>
                {layer && <div ref={layerRef} className="layer layer-in">{layer}</div>}
              </div>
            </div>
          </div>
        </div>
      </div>

      <Compare agents={agents} offline={tw.offline} active={tw.variant} onPick={(v) => setTweak('variant', v)}></Compare>

      <button className="tweaks-toggle" onClick={() => setShowTweaks((s) => !s)}>Tweaks</button>
      {showTweaks && (
        <Tweaks tw={tw} setTweak={setTweak}
          trigger={(key) => {
            const target = {
              claudeEdit: 'default:w1:p1', codexCommand: 'default:w2:p1', claudeAsk: 'default:w2:p3', unknown: 'work:w1:p2',
            }[key];
            const a = agents.find((x) => x.id === target);
            if (!a) return;
            if (a.status === 'blocked') update(target, { status: 'working', interaction: null });
            setTimeout(() => applyChange(target, 'blocked', key), 30);
          }}
          finishOne={() => {
            const w = agents.find((a) => a.status === 'working');
            if (w) applyChange(w.id, 'done');
          }}
          resolveInTerminal={() => {
            const b = selected?.status === 'blocked' ? selected : agents.find((a) => a.status === 'blocked');
            if (b) update(b.id, { status: 'working', interaction: null });
          }}
          reset={() => { setAgents(initialAgents()); setMode('compact'); step.current = 0; }}>
        </Tweaks>
      )}
    </div>
  );
}

// Side-by-side static comparison of the three compact variants with live data.
function Compare({ agents, offline, active, onPick }) {
  const names = { A: 'A · Bird + count', B: 'B · Dot per agent', C: 'C · Tally by status' };
  return (
    <div className="compare" data-screen-label="Compact variants">
      {['A', 'B', 'C'].map((v) => {
        const wing = wingWidth(v, agents);
        return (
          <button key={v} className={`compare-item ${active === v ? 'is-active' : ''}`} onClick={() => onPick(v)}>
            <div className="compare-bar">
              <div className="notch notch-static" style={{ width: PHYS_W + wing * 2, height: BAND_H, borderRadius: '0 0 10px 10px' }}>
                <TopBand variant={v} agents={agents} offline={offline} wing={wing}></TopBand>
              </div>
            </div>
            <span className="compare-label">{names[v]}</span>
          </button>
        );
      })}
    </div>
  );
}

function Seg({ value, options, onChange }) {
  return (
    <div className="seg">
      {options.map(([v, label]) => (
        <button key={v} className={value === v ? 'is-on' : ''} onClick={() => onChange(v)}>{label}</button>
      ))}
    </div>
  );
}

function Tweaks({ tw, setTweak, trigger, finishOne, resolveInTerminal, reset }) {
  return (
    <div className="tweaks">
      <div className="tw-row"><span>Compact</span>
        <Seg value={tw.variant} onChange={(v) => setTweak('variant', v)} options={[['A', 'A'], ['B', 'B'], ['C', 'C']]}></Seg></div>
      <div className="tw-row"><span>List</span>
        <Seg value={tw.density} onChange={(v) => setTweak('density', v)} options={[['hero', 'Hero + rows'], ['compact', 'All rows']]}></Seg></div>
      <div className="tw-row"><span>Agents</span>
        <Seg value={tw.count} onChange={(v) => setTweak('count', v)} options={[['one', '1'], ['normal', '4'], ['many', '7']]}></Seg></div>
      <div className="tw-row"><span>Auto-expand</span>
        <Seg value={tw.autoExpand} onChange={(v) => setTweak('autoExpand', v)} options={[[true, 'On'], [false, 'Off']]}></Seg></div>
      <div className="tw-row"><span>Autoplay</span>
        <Seg value={tw.autoplay} onChange={(v) => setTweak('autoplay', v)} options={[[true, 'On'], [false, 'Off']]}></Seg></div>
      <div className="tw-row"><span>Herdr</span>
        <Seg value={tw.offline} onChange={(v) => setTweak('offline', v)} options={[[false, 'Online'], [true, 'Offline']]}></Seg></div>
      <div className="tw-sep"></div>
      <div className="tw-grid">
        <button onClick={() => trigger('claudeEdit')}>Claude edit</button>
        <button onClick={() => trigger('codexCommand')}>Codex command</button>
        <button onClick={() => trigger('claudeAsk')}>Question</button>
        <button onClick={() => trigger('unknown')}>Unknown prompt</button>
        <button onClick={finishOne}>Finish one</button>
        <button onClick={resolveInTerminal}>Answer in terminal</button>
        <button className={tw.nextStale ? 'is-armed' : ''} onClick={() => setTweak('nextStale', !tw.nextStale)}>
          {tw.nextStale ? 'Stale: armed' : 'Next reply stale'}
        </button>
        <button onClick={reset}>Reset</button>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App></App>);
