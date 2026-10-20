// MacBook screen scaffolding: menu bar + a Herdr (in Ghostty) window as the jump target.

function MenuBar({ clock }) {
  return (
    <div className="menubar">
      <div className="menubar-l">
        <span className="apple"></span>
        <span className="app-name">Ghostty</span>
        <span>File</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span>
      </div>
      <div className="menubar-r">
        <PixelBird tone="idle" size={13} motion={false}></PixelBird>
        <span>{clock}</span>
      </div>
    </div>
  );
}

const HERDR_GLYPH = { blocked: '◉', done: '●', working: '◐', idle: '○' };

function HerdrWindow({ agents, focusedId, flash, raised }) {
  const focused = agents.find((a) => a.id === focusedId) || agents[0];
  const sessions = [...new Set(agents.map((a) => a.session))];
  return (
    <div className={`term ${raised ? 'term-raised' : ''}`}>
      <div className="term-bar">
        <span className="td tr"></span><span className="td ty"></span><span className="td tg"></span>
        <span className="term-title">herdr — {focused ? `${focused.agent} · ${focused.project}` : 'no agents'}</span>
      </div>
      <div className="term-body">
        <div className="herdr-side">
          {sessions.map((s) => (
            <div key={s} className="herdr-session">
              <div className="herdr-session-name">{s}</div>
              {agents.filter((a) => a.session === s).map((a) => (
                <div key={a.id} className={`herdr-agent ${a.id === focusedId ? 'is-focused' : ''} ${a.id === focusedId && flash ? 'is-flash' : ''}`}>
                  <span className={`hg hg-${a.status}`}>{HERDR_GLYPH[a.status]}</span>
                  <span className="ha-name">{a.agent}</span>
                  <span className="ha-proj">{a.project}</span>
                </div>
              ))}
            </div>
          ))}
        </div>
        <div className={`herdr-pane ${flash ? 'is-flash' : ''}`}>
          {focused && <PaneContent a={focused}></PaneContent>}
        </div>
      </div>
    </div>
  );
}

function PaneContent({ a }) {
  const i = a.interaction;
  if (a.status === 'blocked' && i?.kind === 'approval' && i.diff) {
    return (
      <>
        <div className="c-tool">Edit({i.target})</div>
        <div className="c-sep"></div>
        <div className="c-th">Edit file</div>
        {i.diff.map((d, k) => <div key={k} className={`c-code c-${d.t}`}>{d.n}  {d.s}</div>)}
        <div className="c-q">{i.question}</div>
        {i.choices.map((c, k) => <div key={k} className={`c-opt ${k === 0 ? 'c-sel' : ''}`}>{k === 0 ? '❯' : ' '} {k + 1}. {c}</div>)}
      </>
    );
  }
  if (a.status === 'blocked' && i?.kind === 'approval') {
    return (
      <>
        <div className="c-q">{i.question}</div>
        <div className="c-code">{i.command}</div>
        <div className="c-hint">Reason: {i.reason}</div>
        {i.choices.map((c, k) => <div key={k} className={`c-opt ${k === 0 ? 'c-sel' : ''}`}>{k === 0 ? '›' : ' '} {k + 1}. {c}</div>)}
        <div className="c-hint">Press enter to confirm or esc to cancel</div>
      </>
    );
  }
  if (a.status === 'blocked' && i?.kind === 'question') {
    return (
      <>
        <div className="c-r">Build complete. Ready to deploy.</div>
        <div className="c-q">{i.question}</div>
        {i.choices.map((c, k) => <div key={k} className={`c-opt ${k === 0 ? 'c-sel' : ''}`}>{k === 0 ? '❯' : ' '} {k + 1}. {c}</div>)}
        <div className="c-opt">  {i.choices.length + 1}. Type something.</div>
      </>
    );
  }
  if (a.status === 'blocked') {
    return <div className="c-q">{i?.excerpt}</div>;
  }
  if (a.status === 'working') {
    return (
      <>
        <div className="c-r">{a.title}.</div>
        <div className="c-tool">Read(src/…)</div>
        <div className="c-tree">└── 2 files</div>
        <div className="c-hint c-spin">✻ Working… (esc to interrupt)</div>
      </>
    );
  }
  if (a.status === 'done') {
    return (
      <>
        <div className="c-tool">Bash(pnpm test)</div>
        <div className="c-tree">└── <span className="c-ok">8 passed</span></div>
        <div className="c-r">All done — {a.title.toLowerCase()}.</div>
        <div className="c-prompt">❯ </div>
      </>
    );
  }
  return <div className="c-prompt">❯ </div>;
}

Object.assign(window, { MenuBar, HerdrWindow });
