// Mock data shaped after Herdr 0.9.5 AgentInfo fields
// (agent, name, cwd → project, terminal_title_stripped → title, agent_status).
// Perch maps: blocked → Blocked, working → Working, done → Finished, idle/unknown → Idle.

const STATUS = {
  blocked:  { label: 'Blocked',  color: 'var(--vi-alert)',    rank: 0 },
  done:     { label: 'Finished', color: 'var(--vi-idle)',     rank: 1 },
  working:  { label: 'Working',  color: 'var(--vi-work)',     rank: 2 },
  idle:     { label: 'Idle',     color: 'var(--vi-ended)',    rank: 3 },
};

const AGENT_LABEL = { claude: 'Claude', codex: 'Codex', omp: 'OMP', opencode: 'OpenCode' };

// Parsed interactions (what PromptClassifier / ScreenAdapters would produce).
const INTERACTIONS = {
  claudeEdit: {
    kind: 'approval',
    tool: 'Edit',
    target: 'src/auth/middleware.ts',
    diff: [
      { t: 'ctx', n: 12, s: 'const verify = (token) =>' },
      { t: 'del', n: 13, s: '-  jwt.verify(token);' },
      { t: 'add', n: 13, s: "+  if (!token) throw new AuthError('missing');" },
      { t: 'add', n: 14, s: '+  return jwt.verify(token, { maxAge: "1h" });' },
    ],
    stat: '+2 −1',
    question: 'Do you want to make this edit?',
    choices: ['Yes', "Yes, don't ask again this session", 'No'],
  },
  codexCommand: {
    kind: 'approval',
    tool: 'Bash',
    target: 'pnpm test --filter api',
    command: '$ pnpm test --filter api',
    reason: 'Run the API test suite to verify the new endpoints',
    question: 'Would you like to run the following command?',
    choices: ['Yes', 'Yes, and don’t ask again for this command', 'No'],
  },
  claudeAsk: {
    kind: 'question',
    question: 'Which deployment target?',
    choices: ['Production', 'Staging', 'Local only'],
    allowsText: true,
  },
  unknown: {
    kind: 'unknown',
    excerpt: 'Allow write access to ~/.config/omp/settings.json? [y/N]',
  },
};

const now = () => Date.now();
const min = (m) => now() - m * 60000;

function initialAgents() {
  return [
    { id: 'default:w1:p1', session: 'default', agent: 'claude', project: 'herdr-perch',
      title: 'Fix auth token expiry', status: 'working', since: min(27), interaction: null },
    { id: 'default:w2:p1', session: 'default', agent: 'codex', project: 'backend',
      title: 'Add REST endpoints for users', status: 'working', since: min(64), interaction: null },
    { id: 'default:w2:p3', session: 'default', agent: 'claude', project: 'infra',
      title: 'Optimize slow queries', status: 'done', since: min(3), interaction: null },
    { id: 'work:w1:p2', session: 'work', agent: 'omp', project: 'desktop',
      title: 'Update Paneru config', status: 'idle', since: min(41), interaction: null },
  ];
}

function sortAgents(list) {
  return [...list].sort((a, b) =>
    STATUS[a.status].rank - STATUS[b.status].rank || b.since - a.since);
}

function fmtDur(since) {
  const m = Math.max(0, Math.round((now() - since) / 60000));
  if (m < 1) return 'now';
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

// Subline text — only from Herdr fields + parsed interaction headline.
function subline(a) {
  if (a.status === 'blocked') {
    const i = a.interaction;
    if (!i) return 'Needs your input';
    if (i.kind === 'approval') return `Needs approval — ${i.tool} ${i.target}`;
    if (i.kind === 'question') return `Asks — ${i.question}`;
    return 'Needs your input — open in Herdr';
  }
  if (a.status === 'done') return 'Done — click to jump';
  if (a.status === 'working') return 'Working';
  return 'Idle';
}

Object.assign(window, { STATUS, AGENT_LABEL, INTERACTIONS, initialAgents, sortAgents, fmtDur, subline });
