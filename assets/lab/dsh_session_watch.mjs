// assets/lab/dsh_session_watch.mjs
//
// 把 dsh **web 会话**的状态（todo 列表 / 步骤 / 错误）抽成一个纯文本 JSON，
// 给 Flutter 侧轮询 —— 这样在浏览器里聊天也能映射成安卓通知，不需要模型
// 输出任何特殊标记。
//
// 为什么需要它：dsh 把会话落盘成 `sessions/<ws>/session-<uuid>/session.v4.jsonl.zstd`
// （zstd 压缩的 jsonl）。Dart 侧没有可靠的 zstd 库，而 node 22+ 自带
// `zlib.zstdDecompressSync`，所以让 node 解压、Dart 只读一个不压缩的小 JSON。
//
// **它不会被当文件执行**：Dart 侧把源码 base64 后塞进
//   node -e "eval(Buffer.from('<base64>','utf8').toString())"
// —— 因为 Android 的 /sdcard 是 FUSE，应用写出来的文件是 app 私有 0660，
// Shizuku 的 shell 子进程读不了（chmod 也会被 FUSE 挡成 EPERM）。
// 所以用 CJS（require）写法，参数走环境变量 L2A_WATCH_OUT / L2A_WATCH_POLL。
//
// 输出的 JSON：
//   { v, session, title, running, step, todos:[{content,status}], error:{code,message}, text, updatedAt }
// todos 的 status ∈ pending | in_progress | completed
// error 只在 llm/retry 失败时出现（如 TRANSPORT / RATE_LIMIT）

const {
  readFileSync,
  writeFileSync,
  readdirSync,
  statSync,
  renameSync,
} = require('node:fs');
const { join } = require('node:path');
const { zstdDecompressSync } = require('node:zlib');

const home = process.env.DSH_HOME || '';
const outPath = process.env.L2A_WATCH_OUT || '';
const pollMs = Number(process.env.L2A_WATCH_POLL || 1200);

if (!home || !outPath) {
  console.error('missing DSH_HOME / L2A_WATCH_OUT');
  process.exit(2);
}


/** 解压一个「多帧 zstd」文件。
 *
 * dsh 每次写盘是**追加一个新 frame**，而 `zstdDecompressSync` 只解第一帧 ——
 * 直接调用只能拿到第一条事件（踩过：todo 永远是空的）。
 * 这里按 zstd 的 magic 把 buffer 切成一帧一帧，逐帧解再拼起来。
 * magic 出现在压缩数据内部概率 2^-32，可接受。
 */
function decompressAll(buf) {
  const MAGIC = [0x28, 0xb5, 0x2f, 0xfd];
  const starts = [];
  for (let i = 0; i + 3 < buf.length; i++) {
    if (
      buf[i] === MAGIC[0] &&
      buf[i + 1] === MAGIC[1] &&
      buf[i + 2] === MAGIC[2] &&
      buf[i + 3] === MAGIC[3]
    ) {
      starts.push(i);
    }
  }
  if (starts.length <= 1) {
    try {
      return zstdDecompressSync(buf).toString('utf8');
    } catch (e) {
      return '';
    }
  }
  let out = '';
  for (let k = 0; k < starts.length; k++) {
    const start = starts[k];
    const end = k + 1 < starts.length ? starts[k + 1] : buf.length;
    try {
      out += zstdDecompressSync(buf.subarray(start, end)).toString('utf8');
    } catch (e) {
      // 最后一帧可能正在写，忽略
    }
  }
  return out;
}

const sessionsRoot = join(home, 'sessions');

/** 列出所有会话文件，按修改时间倒序（第一个就是"当前会话"）。 */
function listSessions() {
  const found = [];
  let workspaces;
  try {
    workspaces = readdirSync(sessionsRoot);
  } catch {
    return found;
  }
  for (const ws of workspaces) {
    const wsDir = join(sessionsRoot, ws);
    let entries;
    try {
      entries = readdirSync(wsDir);
    } catch {
      continue;
    }
    for (const name of entries) {
      if (!name.startsWith('session-')) continue;
      const file = join(wsDir, name, 'session.v4.jsonl.zstd');
      try {
        const st = statSync(file);
        found.push({ id: name, file, mtime: st.mtimeMs, size: st.size });
      } catch {
        // 会话目录刚建、文件还没落盘
      }
    }
  }
  found.sort((a, b) => b.mtime - a.mtime);
  return found;
}

/** 从解压后的 jsonl 里重建"当前状态"（每条事件都是增量，取最后一次）。 */
function parseState(text) {
  const state = {
    title: '',
    lastUser: '',
    running: false,
    step: 0,
    todos: [],
    error: null,
    text: '',
    // 需要用户回应的东西：模型用 ask_user_question 提问，或者 dsh 请求审批
    question: null,
  };
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let ev;
    try {
      ev = JSON.parse(line);
    } catch {
      continue;
    }
    const d = ev.data || {};
    switch (ev.type) {
      case 'session':
      case 'session/title':
        if (typeof d.title === 'string' && d.title) state.title = d.title;
        break;
      case 'turn/start':
        state.running = true;
        state.error = null;
        break;
      case 'turn/end':
        state.running = false;
        break;
      case 'step/start':
        state.step = Number(d.step) || 0;
        break;
      case 'todo/write':
        if (Array.isArray(d.todos)) {
          state.todos = d.todos.map((t) => ({
            content: String((t && t.content) || '').trim(),
            status: String((t && t.status) || 'pending'),
          }));
        }
        break;
      case 'llm/retry':
        if (d.failure) {
          state.error = {
            code: String(d.failure.code || ''),
            message: String(d.failure.message || ''),
          };
        }
        break;
      case 'user/message':
        if (!state.lastUser) {
          state.lastUser = pickText(d).slice(0, 200);
        }
        break;
      case 'assistant/message':
        {
          const t = pickText(d);
          if (t) state.text = t;
        }
        break;
      case 'tool/call':
        // 模型主动问用户：工具名是 ask_user_question，arguments 是 JSON 字符串
        if (d.name === 'ask_user_question') {
          state.question = parseAsk(d);
        }
        break;
      case 'tool/result':
        // 有结果 = 已经答完了（一次只会有一个待答）。
        if (
          state.question &&
          (!state.question.callId || !(d.callId || d.toolCallId) ||
            String(d.callId || d.toolCallId) === state.question.callId)
        ) {
          state.question = null;
        }
        break;
      case 'approval/asked':
        // dsh 自己的权限审批（跑危险命令时）：也要提醒用户一回
        state.question = state.question || {
          text: String(d.reason || d.description || d.title || '需要你确认'),
          options: [],
        };
        break;
      case 'approval/decided':
        state.question = null;
        break;
      default:
        break;
    }
  }
  return state;
}

/** 把 ask_user_question 的 arguments 拆成「问题 + 选项 + 回答坐标」。
 *
 * 除了给通知展示的文本，还要留下 callId / question id —— 通知里直接回复
 * 时，Dart 侧要用它们调 dsh 的 `userQuestions/answer` RPC。
 */
function parseAsk(d) {
  const raw = d.arguments;
  let arg = {};
  try {
    arg = typeof raw === 'string' ? JSON.parse(raw) : (raw || {});
  } catch (e) {
    return {
      text: String(raw || '').slice(0, 200),
      options: [],
      id: '',
      callId: String(d.callId || d.toolCallId || d.id || ''),
      items: [],
    };
  }
  const list = Array.isArray(arg.questions) && arg.questions.length
    ? arg.questions
    : [arg];
  const items = [];
  for (const q of list) {
    if (!q || typeof q !== 'object') continue;
    const text = String(
      q.question || q.text || q.prompt || q.message || '',
    ).trim();
    let opts = q.options || q.choices || [];
    if (!Array.isArray(opts)) opts = [];
    const options = opts
      .map((o) => (typeof o === 'string' ? o : (o && (o.label || o.value || o.text)) || ''))
      .map((x) => String(x).trim())
      .filter(Boolean)
      .slice(0, 6);
    if (!text && options.length === 0) continue;
    items.push({
      id: String(q.id || ''),
      text: text.slice(0, 300),
      options,
    });
  }
  if (items.length === 0) return null;
  return {
    text: items[0].text,
    options: items[0].options,
    id: items[0].id,
    callId: String(d.callId || d.toolCallId || d.id || ''),
    items,
  };
}

/** 不同版本的事件里正文字段名不一样，挨个试。 */
function pickTextFields(d) {
  for (const key of ['text', 'content', 'message', 'body']) {
    const v = d[key];
    if (typeof v === 'string' && v.trim()) return v.trim();
    if (Array.isArray(v)) {
      const joined = v
        .map((x) => (typeof x === 'string' ? x : (x && x.text) || ''))
        .join('')
        .trim();
      if (joined) return joined;
    }
  }
  return '';
}

/** dsh 0.2 的 assistant/message 把正文放在 data.message.content 里。 */
function pickText(d) {
  const direct = pickTextFields(d);
  if (direct) return direct;
  const message = d && d.message;
  if (message && typeof message === 'object') return pickTextFields(message);
  return '';
}

let lastKey = '';
let lastPayload = '';

function tick() {
  const list = listSessions();
  if (list.length === 0) return;

  // 别直接取 mtime 最新的那个：web 上"新建会话"会立刻落一个只有
  // `{"session":1}` 的空文件，把真正在跑的那个盖住（踩过）。
  // 往后看几个，取第一个真正有事件的。
  let picked = null;
  let pickedText = '';
  for (const candidate of list.slice(0, 6)) {
    let text;
    try {
      text = decompressAll(readFileSync(candidate.file));
    } catch (e) {
      // 文件正在被写、或者压缩帧不完整：跳过，下一轮再来
      continue;
    }
    const lines = text.split('\n').filter((l) => l.trim());
    if (lines.length <= 2) continue; // 空会话（只有 session 头）
    picked = candidate;
    pickedText = text;
    break;
  }
  if (!picked) return;

  const key = `${picked.file}|${picked.mtime}|${picked.size}`;
  if (key === lastKey) return;
  lastKey = key;

  const st = parseState(pickedText);
  const payload = JSON.stringify({
    v: 1,
    session: picked.id,
    title: st.title || st.lastUser.slice(0, 40),
    running: st.running,
    step: st.step,
    todos: st.todos,
    error: st.error,
    question: st.question,
    text: st.text.slice(0, 800),
    updatedAt: Date.now(),
  });
  if (payload === lastPayload) return;
  lastPayload = payload;

  try {
    const tmp = `${outPath}.tmp`;
    writeFileSync(tmp, payload);
    renameSync(tmp, outPath); // 原子替换，Dart 侧不会读到半截
  } catch (e) {
    console.error('write failed:', e && e.message);
  }
}

tick();
setInterval(tick, pollMs);
