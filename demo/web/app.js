import { run_plan_json } from './core.js';

// Display-only labels stay outside the versioned planning document and core API.
const SCENARIOS = {
  student: {
    file: './data/student-plan.v1.json',
    title: '学期安排',
    subtitle: '课程 · 作业 · 考前复习',
    events: {
      'morning-lecture': { name: '数学分析', kind: '课程', place: '理科楼 A203' },
      'afternoon-lecture': { name: '生物实验课', kind: '课程', place: '实验楼 B106' },
      'biology-exam': { name: '生物学期中考试', kind: '考试', place: '综合楼 401' },
    },
    tasks: {
      'topic-announced': '复习范围公布',
      'calculus-homework': '微积分作业',
      'biology-review': '生物考前复习',
      'exam-setup': '考试用品准备',
    },
  },
  project: {
    file: './data/project-plan.v1.json',
    title: '项目交付',
    subtitle: '设计 · 审批 · 发布',
    events: {
      'vendor-call': { name: '供应商沟通', kind: '会议', place: '线上会议室' },
    },
    tasks: {
      design: '交付方案设计',
      approval: '审批完成',
      release: '最终发布',
    },
  },
};

const $ = (selector) => document.querySelector(selector);
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
})[character]);
const pad = (number) => String(number).padStart(2, '0');

let scenarioKey = 'student';
let plan = null;
let displayEvents = {};
let temporaryEventNumber = 0;
let currentResult = null;
let lastValidResult = null;

function dateForMinute(minute) {
  const date = new Date(minute * 60_000);
  return Number.isFinite(date.getTime()) ? date : null;
}

function localTime(minute, includeDate = true) {
  const date = dateForMinute(minute);
  if (!date) return `UTC 分钟 ${minute}`;
  const options = includeDate
    ? { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }
    : { hour: '2-digit', minute: '2-digit', hour12: false };
  return new Intl.DateTimeFormat('zh-CN', options).format(date);
}

function localInput(minute) {
  const date = dateForMinute(minute);
  if (!date) return '';
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function minuteFromInput(value) {
  const milliseconds = new Date(value).getTime();
  return Number.isFinite(milliseconds) ? Math.round(milliseconds / 60_000) : null;
}

function taskName(id) {
  return SCENARIOS[scenarioKey].tasks[id] ?? id;
}

function eventDisplay(event) {
  return displayEvents[event.id] ?? { name: event.id, kind: '固定事件', place: '' };
}

function renderEvents() {
  $('#event-count').textContent = String(plan.fixed_events.length);
  $('#event-list').innerHTML = plan.fixed_events.map((event) => {
    const info = eventDisplay(event);
    const temporary = event.id.startsWith('temporary-');
    const style = info.kind === '考试' ? 'exam' : temporary ? 'temp' : '';
    const icon = info.kind === '考试' ? '✦' : temporary ? '+' : '▣';
    return `<div class="event-mini ${style}"><span class="event-symbol" aria-hidden="true">${icon}</span><div class="event-mini-body"><strong>${escapeHtml(info.name)}</strong><small>${escapeHtml(localTime(event.start))} – ${escapeHtml(localTime(event.end, false))}${info.place ? ` · ${escapeHtml(info.place)}` : ''}</small></div>${temporary ? `<button class="remove-event" type="button" data-event-id="${escapeHtml(event.id)}" aria-label="移除 ${escapeHtml(info.name)}">×</button>` : ''}</div>`;
  }).join('');
}

function renderTaskEditors() {
  $('#task-count').textContent = String(plan.tasks.length);
  const completedIds = new Set(plan.completed.map((record) => record.id));
  const confirmedIds = new Set(plan.confirmed_blocks.map((block) => block.task_id));
  $('#task-list').innerHTML = plan.tasks.map((task, index) => {
    const done = completedIds.has(task.id);
    const confirmed = confirmedIds.has(task.id);
    const status = done ? '已完成' : confirmed ? '部分确认' : '待排程';
    const meta = [task.minimum_block_minutes ? `可拆分 · 最短 ${task.minimum_block_minutes} 分钟` : '连续工作块'];
    if (task.earliest_start !== undefined) meta.push(`最早 ${localTime(task.earliest_start)}`);
    if (task.dependencies.length) meta.push(`前置：${task.dependencies.map(taskName).join('、')}`);
    return `<div class="task-editor"><div class="task-editor-head"><div><h3>${escapeHtml(taskName(task.id))}</h3><span class="task-id">${escapeHtml(task.id)}</span></div><span class="status-chip ${done ? 'done' : ''}">${status}</span></div><p class="task-meta">${escapeHtml(meta.join(' · '))}</p><div class="task-fields"><label>工时 / 分<input class="duration-input" data-task-index="${index}" type="number" min="1" step="1" value="${task.duration_minutes}" ${done ? 'disabled' : ''} /></label><label>截止时间<input class="deadline-input" data-task-index="${index}" type="datetime-local" value="${localInput(task.deadline)}" ${done ? 'disabled' : ''} /></label></div></div>`;
  }).join('');
}

function reasonText(reason) {
  switch (reason.code) {
    case 'NoContinuousSlot': return '现有空档中没有满足工时与截止时间的连续时间块。';
    case 'SplitWorkIncomplete': return `当前已占用时间下仍有 ${reason.remaining_minutes} 分钟无法安排；换一个任务顺序可能有解。`;
    case 'DependencyNotScheduled': return `前置任务 ${taskName(reason.dependency_id)} 未完整安排。`;
    default: return reason.code;
  }
}

function renderTimeline(result) {
  const entries = [
    ...plan.fixed_events.map((event) => ({ ...event, type: 'event' })),
    ...result.blocks.map((block) => ({ ...block, type: 'task' })),
  ];
  entries.sort((a, b) => a.start - b.start || (a.type === 'event' ? -1 : 1));
  $('#timeline').innerHTML = entries.length ? entries.map((entry) => {
    const fixed = entry.type === 'event';
    const info = fixed ? eventDisplay(entry) : null;
    const kind = fixed ? info.kind : entry.confirmed ? '已确认' : '工作块';
    const style = fixed ? `event ${kind === '考试' ? 'exam' : ''}` : entry.confirmed ? 'confirmed' : '';
    const name = fixed ? info.name : taskName(entry.task_id);
    const detail = fixed ? [entry.id, info.place].filter(Boolean).join(' · ') : entry.task_id;
    return `<div class="timeline-item ${style}" data-item-id="${escapeHtml(fixed ? entry.id : entry.task_id)}"><div class="timeline-item-head"><strong>${escapeHtml(name)}</strong><span class="kind-pill">${escapeHtml(kind)}</span></div><div class="timeline-when">${escapeHtml(localTime(entry.start))} — ${escapeHtml(localTime(entry.end))}</div><div class="timeline-detail">${escapeHtml(detail)}</div></div>`;
  }).join('') : '<div class="empty-state">此时间段尚无事件或工作块。</div>';
}

function renderResult() {
  const error = currentResult?.ok ? null : currentResult?.error;
  const banner = $('#validation-banner');
  banner.hidden = !error;
  if (error) {
    banner.innerHTML = `<strong>输入未通过 MoonBit 核心验证</strong><code>${escapeHtml(error.kind)}${error.path ? ` · ${escapeHtml(error.path)}` : ''}</code><br>${escapeHtml(error.message)}<br>下方保留上一次有效排程，仅供对照；请修改或移除冲突输入。`;
  }
  const shown = currentResult?.ok ? currentResult : lastValidResult;
  $('#metric-blocks').textContent = shown ? String(shown.blocks.length) : '—';
  $('#metric-confirmed').textContent = shown ? String(shown.blocks.filter((block) => block.confirmed).length) : '—';
  $('#metric-unscheduled').textContent = shown ? String(shown.unscheduled.length) : '—';
  if (shown) renderTimeline(shown);
  else $('#timeline').innerHTML = '<div class="empty-state">尚无有效排程。</div>';
  $('#unscheduled-list').innerHTML = !shown
    ? '<div class="empty-state">请修正输入后重新排程。</div>'
    : shown.unscheduled.length
      ? shown.unscheduled.map((item) => `<div class="unscheduled-item" data-unscheduled-id="${escapeHtml(item.task_id)}"><strong>${escapeHtml(taskName(item.task_id))}</strong><span>${escapeHtml(reasonText(item.reason))} <code>${escapeHtml(item.reason.code)}</code></span></div>`).join('')
      : '<div class="all-good">所有待办任务均已安排；已完成任务不再占用时间。</div>';
}

function recalculate() {
  // The only planning call in the browser: JSON -> MoonBit parser -> public scheduler.
  currentResult = JSON.parse(run_plan_json(JSON.stringify(plan)));
  if (currentResult.ok) lastValidResult = currentResult;
  renderResult();
}

async function loadScenario(key) {
  const scenario = SCENARIOS[key];
  const response = await fetch(scenario.file);
  if (!response.ok) throw new Error(`无法读取 ${scenario.file}: HTTP ${response.status}`);
  const nextPlan = await response.json();
  scenarioKey = key;
  plan = nextPlan;
  displayEvents = { ...scenario.events };
  temporaryEventNumber = 0;
  currentResult = null;
  lastValidResult = null;
  $('#scenario-title').textContent = scenario.title;
  $('#scenario-subtitle').textContent = scenario.subtitle;
  for (const button of document.querySelectorAll('.scenario-button')) {
    const active = button.dataset.scenario === key;
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  }
  $('#day-caption').textContent = `示例开放时间：${localTime(plan.availability[0].start)} — ${localTime(plan.availability.at(-1).end)}；按实际开始时间排列。`;
  $('#event-start').value = localInput(plan.availability[0].start + 180);
  $('#event-end').value = localInput(plan.availability[0].start + 210);
  $('#event-form').reset();
  $('#event-start').value = localInput(plan.availability[0].start + 180);
  $('#event-end').value = localInput(plan.availability[0].start + 210);
  renderEvents();
  renderTaskEditors();
  recalculate();
}

$('#timezone-label').textContent = `浏览器本地时间 · ${Intl.DateTimeFormat().resolvedOptions().timeZone}`;
document.querySelectorAll('.scenario-button').forEach((button) => button.addEventListener('click', () => {
  loadScenario(button.dataset.scenario).catch(showLoadError);
}));
$('#task-list').addEventListener('input', (event) => {
  const input = event.target;
  const index = Number(input.dataset.taskIndex);
  if (!Number.isInteger(index) || !plan?.tasks[index]) return;
  if (input.classList.contains('duration-input')) {
    if (input.value === '') return;
    plan.tasks[index].duration_minutes = Number(input.value);
  } else if (input.classList.contains('deadline-input')) {
    if (!input.value) return;
    plan.tasks[index].deadline = minuteFromInput(input.value);
  } else return;
  recalculate();
});
$('#event-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const id = `temporary-${++temporaryEventNumber}`;
  plan.fixed_events.push({ id, start: minuteFromInput($('#event-start').value), end: minuteFromInput($('#event-end').value) });
  displayEvents[id] = { name: $('#event-name').value.trim(), kind: '临时', place: $('#event-place').value.trim() };
  renderEvents();
  recalculate();
});
$('#event-list').addEventListener('click', (event) => {
  const button = event.target.closest('.remove-event');
  if (!button) return;
  plan.fixed_events = plan.fixed_events.filter((item) => item.id !== button.dataset.eventId);
  delete displayEvents[button.dataset.eventId];
  renderEvents();
  recalculate();
});

function showLoadError(error) {
  $('#validation-banner').hidden = false;
  $('#validation-banner').textContent = `示例加载失败：${error.message}`;
}

// Useful for repeatable local browser checks; no scheduling implementation is exposed here.
window.__deadlineplanDemo = { getState: () => ({ scenario: scenarioKey, plan, result: currentResult }) };
loadScenario('student').catch(showLoadError);
