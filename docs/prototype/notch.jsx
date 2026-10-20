// Presentational notch pieces. Layout and tokens follow vibeisland.app's demo notch.

const PHYS_W = 186; // physical camera housing width (pt, scaled)
const BAND_H = 32;  // menu-bar height = physical notch height

function topTone(agents, offline) {
  if (offline) return 'offline';
  const first = sortAgents(agents)[0];
  if (!first) return 'idle';
  if (first.status === 'blocked') return first.interaction?.kind === 'question' ? 'question' : 'blocked';
  return first.status;
}

function statusColor(a) {
  if (a.status === 'blocked' && a.interaction?.kind === 'question') return 'var(--vi-question)';
  return STATUS[a.status].color;
}

// ── Compact wings (three variants) ───────────────────────────────────────────
function wingWidth(variant, agents) {
  if (variant === 'A') return 40;
  if (variant === 'B') return Math.max(40, Math.min(agents.length, 6) * 10 + 22);
  const groups = new Set(agents.map((a) => a.status)).size;
  return Math.max(40, groups * 24 + 16);
}

function CompactRight({ variant, agents, offline }) {
  const sorted = sortAgents(agents);
  if (variant === 'A') {
    const urgent = agents.filter((a) => a.status === 'blocked').length;
    return (
      <span className={`wing-count ${urgent ? 'is-alert' : ''}`}>{agents.length}</span>
    );
  }
  if (variant === 'B') {
    const shown = sorted.slice(0, 6);
    return (
      <span className="wing-dots">
        {shown.map((a) => (
          <span key={a.id} className={`wdot wdot-${a.status}`} style={{ background: offline ? '#444' : statusColor(a) }}></span>
        ))}
        {sorted.length > 6 && <span className="wing-more">+{sorted.length - 6}</span>}
      </span>
    );
  }
  const order = ['blocked', 'done', 'working', 'idle'];
  return (
    <span className="wing-tally">
      {order.map((s) => {
        const n = agents.filter((a) => a.status === s).length;
        if (!n) return null;
        return (
          <span key={s} className={`tally tally-${s}`}>
            <span className="tdot" style={{ background: offline ? '#444' : STATUS[s].color }}></span>
            <span className="tnum">{n}</span>
          </span>
        );
      })}
    </span>
  );
}

function TopBand({ variant, agents, offline, wing }) {
  return (
    <div className="band" style={{ height: BAND_H }}>
      <div className="band-l" style={{ width: wing }}>
        <PixelBird tone={topTone(agents, offline)} size={16}></PixelBird>
      </div>
      <div className="band-gap" style={{ width: PHYS_W }}></div>
      <div className="band-r" style={{ width: wing }}>
        {agents.length > 0 && <CompactRight variant={variant} agents={agents} offline={offline}></CompactRight>}
      </div>
    </div>
  );
}

function shortStatus(a) {
  if (a.status === 'done') return 'Done';
  const k = a.interaction?.kind;
  return k === 'approval' ? 'Approve?' : k === 'question' ? 'Asks' : 'Input';
}

// ── Overview list ────────────────────────────────────────────────────────────
function Tags({ a, multiSession }) {
  return (
    <>
      <span className="tag">{AGENT_LABEL[a.agent] || a.agent}</span>
      <span className="tag">{a.project}</span>
      {multiSession && <span className="tag tag-session">{a.session}</span>}
      <span className="dur">{fmtDur(a.since)}</span>
    </>
  );
}

function HeroRow({ a, multiSession, onClick, offline }) {
  const tone = a.status === 'blocked' && a.interaction?.kind === 'question' ? 'question' : a.status;
  return (
    <div className={`sess sess-hero ${a.status === 'done' ? 'sess-hl' : ''}`} onClick={onClick}>
      <PixelBird tone={offline ? 'offline' : tone} size={16}></PixelBird>
      <div className="si">
        <div className="sess-r1">
          <span className="sn">{a.title}</span>
          <Tags a={a} multiSession={multiSession}></Tags>
        </div>
        <div className="ss" style={{ color: offline ? '#666' : statusColor(a) }}>
          {a.status === 'blocked' && <span className="ss-pulse"></span>}
          {subline(a)}
        </div>
      </div>
      <span className="row-affordance">{a.status === 'blocked' ? '›' : '↗'}</span>
    </div>
  );
}

function MiniRow({ a, multiSession, onClick, offline }) {
  return (
    <div className="sess sess-mini" onClick={onClick}>
      <span className={`sd sd-${a.status}`} style={{ background: offline ? '#444' : statusColor(a) }}></span>
      <span className="sn">{a.title}</span>
      {(a.status === 'blocked' || a.status === 'done') && (
        <span className="mini-status" style={{ color: offline ? '#666' : statusColor(a) }}>{shortStatus(a)}</span>
      )}
      <span className="sess-tags"><Tags a={a} multiSession={multiSession}></Tags></span>
      <span className="row-affordance">{a.status === 'blocked' ? '›' : '↗'}</span>
    </div>
  );
}

function Overview({ agents, density, multiSession, offline, onRow }) {
  const sorted = sortAgents(agents);
  if (!sorted.length) {
    return <div className="empty">No agents in Herdr</div>;
  }
  return (
    <div className="overview">
      {offline && <div className="notice">Herdr isn’t reachable — reconnecting…</div>}
      {sorted.map((a, i) =>
        density === 'hero' && i === 0
          ? <HeroRow key={a.id} a={a} multiSession={multiSession} offline={offline} onClick={() => onRow(a)}></HeroRow>
          : <MiniRow key={a.id} a={a} multiSession={multiSession} offline={offline} onClick={() => onRow(a)}></MiniRow>
      )}
    </div>
  );
}

// ── Interaction cards ────────────────────────────────────────────────────────
function CardHead({ a, label, color, onBack, extra }) {
  return (
    <div className="card-head">
      {onBack && <button className="back" onClick={onBack} aria-label="Back">‹</button>}
      <span className="head-dot" style={{ background: color }}></span>
      <span className="head-label" style={{ color }}>{label}</span>
      <span className="head-meta">{label.startsWith(AGENT_LABEL[a.agent]) ? a.project : `${AGENT_LABEL[a.agent] || a.agent} · ${a.project}`}</span>
      {extra}
    </div>
  );
}

function Notice({ text }) {
  if (!text) return null;
  return <div className="card-notice">{text}</div>;
}

function ApprovalCard({ a, onChoose, onBack, onOpen, sending, notice }) {
  const i = a.interaction;
  const hasAlways = i.choices.length > 2;
  return (
    <div className="card">
      <CardHead a={a} label="Permission Request" color="var(--vi-alert)" onBack={onBack}
        extra={<button className="open-link" onClick={onOpen}>Open in Herdr ↗</button>}></CardHead>
      <div className="appr-tool">
        <span className="appr-icon">⚠</span>
        <span className="appr-name">{i.tool}</span>
        <span className="appr-input">{i.target}</span>
      </div>
      {i.diff && (
        <div className="appr-ctx">
          <div className="diff">
            {i.diff.map((d, k) => (
              <div key={k} className={`diff-line diff-${d.t}`}><span className="diff-ln">{d.n}</span>{d.s}</div>
            ))}
          </div>
          <span className="appr-diff">{i.stat}</span>
        </div>
      )}
      {i.command && (
        <div className="appr-ctx">
          <div className="diff"><div className="diff-line diff-cmd">{i.command}</div></div>
          <span className="appr-diff">{i.reason}</span>
        </div>
      )}
      <Notice text={notice}></Notice>
      <div className="appr-btns">
        <button className="btn-deny" disabled={!!sending} onClick={() => onChoose('deny')}>
          {sending === 'deny' ? <span className="spin"></span> : 'Deny'} <kbd>esc</kbd>
        </button>
        {hasAlways && (
          <button className="btn-always" disabled={!!sending} onClick={() => onChoose(1)} title={i.choices[1]}>
            {sending === 1 ? <span className="spin"></span> : 'Always'} <kbd>2</kbd>
          </button>
        )}
        <button className="btn-allow" disabled={!!sending} onClick={() => onChoose(0)}>
          {sending === 0 ? <span className="spin dark"></span> : 'Allow'} <kbd>↩</kbd>
        </button>
      </div>
    </div>
  );
}

function AskCard({ a, onChoose, onText, onBack, onOpen, sending, notice }) {
  const i = a.interaction;
  const [text, setText] = React.useState('');
  return (
    <div className="card">
      <CardHead a={a} label={`${AGENT_LABEL[a.agent]} asks`} color="var(--vi-question)" onBack={onBack}
        extra={<button className="open-link" onClick={onOpen}>Open in Herdr ↗</button>}></CardHead>
      <div className="ask-q">{i.question}</div>
      <Notice text={notice}></Notice>
      <div className="ask-opts">
        {i.choices.map((c, k) => (
          <button key={k} className="ask-opt" disabled={!!sending} onClick={() => onChoose(k)}>
            <span className="ask-num">{sending === k ? <span className="spin"></span> : k + 1}</span>
            <span>{c}</span>
          </button>
        ))}
        {i.allowsText && (
          <form className="ask-text" onSubmit={(e) => { e.preventDefault(); if (text.trim()) onText(text.trim()); }}>
            <span className="ask-num ask-num-ghost">{i.choices.length + 1}</span>
            <input value={text} onChange={(e) => setText(e.target.value)} placeholder="Type something…" disabled={!!sending}></input>
          </form>
        )}
      </div>
    </div>
  );
}

function FallbackCard({ a, onBack, onOpen }) {
  return (
    <div className="card">
      <CardHead a={a} label="Needs your input" color="var(--vi-alert)" onBack={onBack}></CardHead>
      <div className="fallback-text">Perch can’t safely read this prompt. Answer it in Herdr.</div>
      <div className="diff"><div className="diff-line diff-ctx">{a.interaction.excerpt}</div></div>
      <div className="appr-btns">
        <button className="btn-allow" onClick={onOpen}>Open in Herdr ↗</button>
      </div>
    </div>
  );
}

function Feedback({ text, color }) {
  return (
    <div className="feedback">
      <span style={{ color, fontSize: 15 }}>✓</span>
      <span style={{ color, fontWeight: 600 }}>{text}</span>
    </div>
  );
}

Object.assign(window, {
  PHYS_W, BAND_H, wingWidth, TopBand, Overview, ApprovalCard, AskCard, FallbackCard, Feedback,
});
