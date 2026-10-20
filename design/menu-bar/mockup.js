// Offline design prototype. All actions are simulated; no clipboard or network APIs.
const paths = {
  clipboard:
    '<path d="M9 5H6a2 2 0 0 0-2 2v13h13V7a2 2 0 0 0-2-2h-2"/><rect x="8" y="3" width="6" height="4" rx="1"/><path d="M8 13l3-3 3 3m-3-3v7"/>',
  board: '<path d="M8 5H5v16h14V5h-3"/><rect x="8" y="3" width="8" height="4" rx="1"/>',
  upload: '<path d="M12 16V3m-5 5 5-5 5 5M5 16v5h14v-5"/>',
  download: '<path d="M12 3v13m-5-5 5 5 5-5M5 17v4h14v-4"/>',
  arrow: '<path d="M4 12h16m-5-5 5 5-5 5"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  error: '<path d="M12 8v6m0 3v.1"/><path d="m12 3 10 18H2Z"/>',
  bang: '<path d="M12 5v9m0 4v.2"/>',
  folder: '<path d="M3 7h7l2 2h9v11H3Z"/><path d="M3 7V4h7l2 3h9v2"/>',
  search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
  copy: '<rect x="8" y="8" width="12" height="13" rx="1"/><path d="M15 8V3H3v13h5"/>',
  settings:
    '<circle cx="12" cy="12" r="4"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M5 19l2-2M17 7l2-2"/><circle cx="12" cy="12" r="8"/>',
  exit: '<path d="M10 4H4v16h6m4-12 4 4-4 4m-5-4h12"/>',
  wifi: '<path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8 16a6 6 0 0 1 8 0m-4 4v.1"/>',
  play: '<path d="m7 3 14 9-14 9Z"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
  spinner: '<path d="M12 3a9 9 0 1 1-9 9"/>',
};
const menuVariants = [
  {
    id: 'A',
    title: '紧凑双行',
    description:
      '<strong>最接近现在的菜单。</strong>首行保留结果与文件，次行统一放方向、大小、时间。改动最小，但信息仍然比较密。',
  },
  {
    id: 'B',
    title: '分层摘要',
    description:
      '<strong>推荐：层次清楚，文件仍可见。</strong>第一行是结果与时间，第二行是文件，第三行是去向与大小。比双行多一点高度，扫描更轻松。',
  },
  {
    id: 'C',
    title: '摘要优先',
    description:
      '<strong>最安静，也最省空间。</strong>只显示结果、内容类型与方向。文件名收进详情，适合主要同步截图、不依赖文件名确认的习惯。',
  },
];
const iconVariants = [
  { id: 'dot', title: '① 旁边圆点', description: '蓝点进行中，绿点完成，红点失败。配合符号变化，不能仅靠颜色判断。' },
  { id: 'tint', title: '② 整体变色', description: '反馈最显眼。壁纸、选中态和色觉差异都会影响辨识，需要额外验证。' },
  {
    id: 'badge',
    title: '③ 右下角徽标',
    description: '保留主图标，叠加方向、对号或感叹号。语义直接，真实尺寸下细节偏小。',
  },
  {
    id: 'mono',
    title: '④ 单色切换',
    description: '推荐：方向箭头 → 对号 → 默认图标。像素利用率高，操作期间暂时弱化品牌识别。',
  },
];
const stateLabels = { idle: '待机', upload: '上传中', download: '接收中', success: '已完成', error: '失败' };
const samples = {
  image: { name: '7d388c7dfb1f3a5d3fefefe810a832ad.png', type: '图像', size: '247.3 KB', sync: true },
  long: {
    name: '项目界面设计评审截图_设置页_最终确认版_2026-10-20_7d388c7dfb1f3a5d3fefefe810a832ad.png',
    type: '图像',
    size: '1.8 MB',
    sync: true,
  },
  files: { name: 'gapless-paste-menu-bar-design-review-final.png', type: '3 个文件', size: '4.2 MB', sync: false },
  text: { name: '', type: '文本', size: '1,248 字', sync: true },
  empty: { name: '', type: '', size: '', sync: true },
};
const ui = {
  menu: 'B',
  icon: 'mono',
  state: 'idle',
  scenario: 'image',
  direction: 'upload',
  theme: 'light',
  recent: false,
  acknowledged: false,
  playing: false,
  timers: [],
};
const $ = (selector) => document.querySelector(selector);
const escapeHTML = (text) =>
  String(text).replace(
    /[&<>"']/g,
    (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char],
  );
function symbol(name, className = '') {
  return `<svg class="symbol ${className}" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.clipboard}</svg>`;
}
function iconMarkup(variant, state) {
  const busy = state === 'upload' || state === 'download';
  const glyph = state === 'idle' ? 'clipboard' : state;
  const shape = state === 'success' ? 'check' : glyph;
  const tone = state === 'idle' ? '' : `tone-${state}`;
  const motion = busy ? 'motion-symbol' : '';
  if (variant === 'mono') {
    return `<span class="status-icon ${busy ? 'is-busy' : ''}">${symbol(shape, motion)}</span>`;
  }
  if (variant === 'badge') {
    const badge =
      state === 'idle' ? '' : `<span class="badge">${symbol(state === 'error' ? 'bang' : shape, motion)}</span>`;
    return `<span class="status-icon ${busy ? 'is-busy' : ''}">${symbol('clipboard')}${badge}</span>`;
  }
  const innerShape = state === 'idle' ? 'clipboard' : shape;
  if (variant === 'tint')
    return `<span class="status-icon ${tone} ${busy ? 'is-busy' : ''}">${symbol(innerShape, motion)}</span>`;
  const dot = state === 'idle' ? '' : `<i class="dot ${tone}" aria-hidden="true"></i>`;
  return `<span class="status-icon ${busy ? 'is-busy' : ''}">${symbol(innerShape, motion)}${dot}</span>`;
}
function currentRecord() {
  const sample = samples[ui.scenario];
  const empty = ui.scenario === 'empty';
  const busy = ui.state === 'upload' || ui.state === 'download';
  const receiving = ui.direction === 'download';
  const name = (sample.name && $('#filename').value.trim()) || sample.name;
  const destination = sample.sync ? 'mini' : 'mini / inbox';
  const route = receiving ? 'mini → 本机' : `本机 → ${destination}`;
  let title = sample.sync ? '已同步到远端' : '已上传到远端';
  if (receiving) title = '已接收到本机';
  if (busy) title = receiving ? '正在接收剪贴板…' : sample.sync ? '正在同步到远端…' : '正在上传文件…';
  if (ui.state === 'error') title = receiving ? '接收失败' : '传输失败';
  if (empty) title = '还没有传输记录';
  const time = busy || empty ? '' : ui.state === 'error' || ui.state === 'success' || ui.recent ? '刚刚' : '14 小时前';
  const content =
    ui.scenario === 'text'
      ? `文本 · ${sample.size}`
      : ui.scenario === 'files'
        ? `3 个文件 · ${sample.size}`
        : sample.type;
  return { ...sample, name, empty, busy, receiving, route, title, time, content };
}
function filenameMarkup(record) {
  if (record.type === '文本') return '<span class="single-line">文本剪贴板 · 1,248 字</span>';
  const suffix = ui.scenario === 'files' ? ' 等 3 个文件' : '';
  return `<span class="file-name single-line" data-full="${escapeHTML(record.name)}" data-suffix="${suffix}" title="${escapeHTML(record.name)}">${escapeHTML(record.name + suffix)}</span>`;
}
function summaryMarkup(variant, record) {
  if (record.empty)
    return `<div class="summary-block"><span class="state-mark">${symbol('clock')}</span><div class="result-title">${record.title}</div><div class="meta">选择下方操作，开始第一次传输</div></div>`;
  const mark = record.busy ? symbol('spinner', 'rotating') : symbol(ui.state === 'error' ? 'error' : 'check');
  const meta = `<span>${escapeHTML(record.route)}</span><span>· ${record.size}</span>`;
  const filename = filenameMarkup(record);
  let contents;
  if (variant === 'A') {
    const prefix = record.busy ? '进行中' : ui.state === 'error' ? '失败' : '上次';
    contents = `<div class="compact-title"><span>${prefix}：</span>${filename}</div><div class="meta single-line">${escapeHTML(record.route)} · ${record.size}${record.time ? ' · ' + record.time : ''}</div>`;
  } else if (variant === 'B') {
    contents = `<div class="meta-top"><span class="result-title">${record.title}</span><span class="time">${record.time}</span></div><div class="filename">${filename}</div><div class="meta route">${meta}</div>`;
  } else {
    contents = `<div class="result-title">${record.title}</div><div class="meta single-line">${record.type} · ${escapeHTML(record.route)}${record.time ? ' · ' + record.time : ''}</div>`;
  }
  return `<div class="summary-block"><span class="state-mark">${mark}</span>${contents}</div>`;
}
function action(label, icon, options = {}) {
  return `<button type="button" class="menu-action" data-action="${options.action || 'demo'}" ${options.disabled ? 'disabled' : ''}>${icon ? symbol(icon) : ''}<span>${label}</span>${options.shortcut ? `<span class="shortcut">${options.shortcut}</span>` : ''}</button>`;
}
function detailMarkup(record, variant) {
  if (record.empty) return '';
  return `<details data-detail="${variant}">
    <summary class="menu-action">查看${ui.state === 'error' ? '失败' : '传输'}详情</summary>
    <div class="transfer-detail">
      ${record.name ? `<b>完整文件名</b><br>${escapeHTML(record.name)}${ui.scenario === 'files' ? '<br>notes.md<br>config-example.json' : ''}<br>` : '<b>内容</b><br>纯文本，1,248 字；不展示文本正文。<br>'}
      <b>操作</b><br>${escapeHTML(record.route)} · ${record.sync ? '剪贴板同步' : '目录上传'}<br>
      <b>状态</b><br>${record.title}${record.time ? ' · ' + record.time : ''}
      ${ui.state === 'error' ? '<br><b>失败原因</b><br>连接 mini 超时。请检查网络与 SSH 连接后重试。' : ''}
    </div>
  </details>`;
}
function nativeMenu(variant, record) {
  const iconState = ui.acknowledged && ui.state === 'error' ? 'idle' : ui.state;
  const canCopy = !record.empty && !record.sync && !record.busy && ui.state !== 'error';
  return `<div class="desktop" data-theme="${ui.theme}">
    <div class="menubar"><button type="button" class="status-button open" title="GaplessPaste · ${stateLabels[iconState]}" aria-label="GaplessPaste · ${stateLabels[iconState]}；菜单已展开" data-action="status">${iconMarkup(ui.icon, iconState)}</button>${symbol('wifi')}<span>周二 10:24</span></div>
    <div class="native-menu" aria-label="方案 ${variant} 的模拟菜单">
      ${summaryMarkup(variant, record)}
      ${detailMarkup(record, variant)}
      ${action('拷贝上次上传的远端路径', 'copy', { disabled: !canCopy, action: 'copy' })}
      ${ui.state === 'error' ? action('重试上次操作', '', { action: 'retry' }) : ''}
      <hr><div class="machine-header">mini</div>
      ${action('同步到远端剪贴板 →', '', { disabled: record.busy, action: 'upload' })}
      ${action('从远端剪贴板同步 ←', '', { disabled: record.busy, action: 'download' })}
      ${action('预览远端目录…', 'search')}
      ${action('inbox', 'folder', { disabled: record.busy, action: 'file-upload' })}
      ${action('screenshots', 'folder', { disabled: record.busy, action: 'file-upload' })}
      <hr>
      ${action('设置…', 'settings', { shortcut: '⌘ ,' })}
      ${action('重载配置')}
      ${action('打开日志')}
      ${action('检查更新…')}
      ${action('退出', 'exit', { shortcut: '⌘ Q' })}
    </div>
  </div>`;
}
function renderMenus() {
  const record = currentRecord();
  $('#menu-options').innerHTML = menuVariants
    .map(
      (variant) => `<article class="menu-option">
    <div class="option-heading"><h3>${variant.id} · ${variant.title}</h3><button class="choice-button" data-menu="${variant.id}" aria-pressed="${ui.menu === variant.id}" type="button">${ui.menu === variant.id ? '已选' : '选择'}</button></div>
    ${nativeMenu(variant.id, record)}
    <p class="option-description">${variant.description}</p>
  </article>`,
    )
    .join('');
  requestAnimationFrame(fitFilenames);
}
const measureCanvas = document.createElement('canvas');
const measureContext = measureCanvas.getContext('2d');
const segmenter = new Intl.Segmenter('zh-CN', { granularity: 'grapheme' });
function fitFilenames() {
  document.querySelectorAll('[data-full]').forEach((element) => {
    const full = element.dataset.full;
    const suffix = element.dataset.suffix;
    const width = element.clientWidth || element.parentElement.clientWidth;
    measureContext.font = getComputedStyle(element).font;
    const fits = (text) => measureContext.measureText(text).width <= width;
    if (fits(full + suffix)) {
      element.textContent = full + suffix;
      return;
    }
    const letters = Array.from(segmenter.segment(full), (part) => part.segment);
    let keep = letters.length - 1;
    let candidate = '';
    while (keep > 1) {
      const tail = Math.min(Math.max(7, Math.floor(keep * 0.4)), keep - 1);
      candidate = letters.slice(0, keep - tail).join('') + '…' + letters.slice(-tail).join('') + suffix;
      if (fits(candidate)) break;
      keep -= 1;
    }
    element.textContent = candidate;
  });
}
function renderIcons() {
  const states = Object.keys(stateLabels);
  $('#icon-matrix').dataset.theme = ui.theme;
  $('#icon-matrix').innerHTML =
    `<div class="matrix-row matrix-header"><span>方案 / 取舍</span>${states.map((state) => `<span>${stateLabels[state]}</span>`).join('')}</div>` +
    iconVariants
      .map(
        (variant) => `<div class="matrix-row">
      <div class="matrix-label"><h3>${variant.title}<button type="button" class="choice-button" data-icon="${variant.id}" aria-pressed="${ui.icon === variant.id}">${ui.icon === variant.id ? '已选' : '选择'}</button></h3><p>${variant.description}</p></div>
      ${states.map((state) => `<div class="icon-cell" data-current="${ui.state === state}"><div class="icon-sample"><button type="button" class="status-button" data-state="${state}" aria-label="${variant.title} · ${stateLabels[state]}" title="${stateLabels[state]}">${iconMarkup(variant.id, state)}</button></div></div>`).join('')}
    </div>`,
      )
      .join('');
}
function renderSelection() {
  const menu = menuVariants.find((item) => item.id === ui.menu);
  const icon = iconVariants.find((item) => item.id === ui.icon);
  $('#selection').innerHTML =
    `${symbol('check')}当前组合：${menu.id} · ${menu.title} ＋ ${icon.title}。可以直接用这个编号告诉我你的选择。`;
}
function render() {
  document
    .querySelectorAll('.segmented [data-state]')
    .forEach((button) => button.setAttribute('aria-pressed', button.dataset.state === ui.state));
  renderMenus();
  renderIcons();
  renderSelection();
}
function announce(message) {
  $('#demo-status').textContent = message;
}
function stopPlayback() {
  ui.timers.forEach(clearTimeout);
  ui.timers = [];
  ui.playing = false;
  $('#play').innerHTML = `${symbol('play')}播放一次传输`;
}
function setScenario(scenario) {
  ui.scenario = scenario;
  $('#scenario').value = scenario;
  $('#filename').value = samples[scenario].name;
  $('#filename').disabled = scenario === 'text' || scenario === 'empty';
}
function changeState(state, fromPlayback = false) {
  if (!fromPlayback) stopPlayback();
  if (ui.scenario === 'empty' && state !== 'idle') setScenario('image');
  // Receiving clipboard content cannot produce the multi-file upload fixture.
  if (state === 'download' && ui.scenario === 'files') setScenario('image');
  if (state === 'upload' || state === 'download') ui.direction = state;
  ui.state = state;
  ui.acknowledged = false;
  if (state === 'success') ui.recent = true;
  render();
  const notes = {
    idle: '菜单栏图标处于待机；菜单仍保留最近一次结果。',
    upload: '正在向远端传输。上传和同步操作暂时禁用，预览目录仍然可用。',
    download: '正在从 mini 接收。方向反转；本地剪贴板写入成功后才显示完成。',
    success: '成功状态预览。手动选择会停留；点击「播放一次传输」可体验 2 秒后恢复待机。',
    error: '失败提示保留。打开任一「查看失败详情」可确认提醒，或点击「重试上次操作」。',
  };
  announce(notes[state]);
}
function play(direction = ui.direction) {
  stopPlayback();
  ui.playing = true;
  $('#play').innerHTML = `${symbol('clock')}停止演示`;
  changeState(direction, true);
  announce('演示进行中：传输 2 秒 → 成功反馈 2 秒 → 恢复待机。');
  ui.timers.push(
    setTimeout(() => {
      changeState('success', true);
      announce('传输与剪贴板写入已完成，对号保留 2 秒。');
    }, 2000),
  );
  ui.timers.push(
    setTimeout(() => {
      changeState('idle', true);
      stopPlayback();
      announce('演示结束：图标恢复待机，菜单保留刚刚完成的结果。');
    }, 4000),
  );
}
document.addEventListener('click', (event) => {
  const button = event.target.closest('button');
  if (!button || button.disabled) return;
  if (button.dataset.state) changeState(button.dataset.state);
  if (button.dataset.menu) {
    ui.menu = button.dataset.menu;
    render();
  }
  if (button.dataset.icon) {
    ui.icon = button.dataset.icon;
    render();
  }
  const actionName = button.dataset.action;
  if (actionName === 'upload' || actionName === 'download') {
    if (actionName === 'upload' && ui.scenario === 'files') setScenario('image');
    play(actionName);
  }
  if (actionName === 'file-upload') {
    setScenario('files');
    play('upload');
  }
  if (actionName === 'retry') play();
  if (actionName === 'copy') announce('模拟：已拷贝 3 个远端文件路径。此设计稿不会读取或覆盖你的真实剪贴板。');
  if (actionName === 'demo')
    announce(`「${button.innerText.trim()}」是原生应用的现有操作；这份设计稿只演示布局与传输状态。`);
  if (actionName === 'status') announce('这里展示菜单展开时的系统前景色；下方图标矩阵展示菜单关闭时的真实状态配色。');
});
document.addEventListener(
  'toggle',
  (event) => {
    if (!event.target.matches('details[data-detail]') || !event.target.open || ui.state !== 'error') return;
    ui.acknowledged = true;
    document.querySelectorAll('.menubar .status-button').forEach((button) => {
      button.innerHTML = iconMarkup(ui.icon, 'idle');
      button.setAttribute('aria-label', 'GaplessPaste · 待机；失败详情已查看');
      button.title = 'GaplessPaste · 待机';
    });
    announce('失败详情已查看：菜单栏提醒已清除，菜单中的失败记录和重试入口继续保留。下方矩阵仍用于比较各状态样式。');
  },
  true,
);
$('#scenario').addEventListener('change', (event) => {
  stopPlayback();
  setScenario(event.target.value);
  ui.state = 'idle';
  ui.direction = 'upload';
  ui.recent = false;
  ui.acknowledged = false;
  render();
  announce(
    ui.scenario === 'empty'
      ? '首次使用状态：先选择同步或目录上传。'
      : '已更换内容样例，当前显示 14 小时前的上次成功结果。',
  );
});
$('#filename').addEventListener('input', renderMenus);
$('#appearance').addEventListener('change', (event) => {
  ui.theme = event.target.value;
  render();
});
$('#enlarge').addEventListener('change', (event) =>
  $('#icon-matrix').classList.toggle('enlarged', event.target.checked),
);
$('#reduce-motion').checked = matchMedia('(prefers-reduced-motion: reduce)').matches;
document.body.classList.toggle('reduce-motion', $('#reduce-motion').checked);
$('#reduce-motion').addEventListener('change', (event) =>
  document.body.classList.toggle('reduce-motion', event.target.checked),
);
$('#play').addEventListener('click', () => {
  if (ui.playing) {
    stopPlayback();
    announce('演示已停止，可以手动切换状态。');
  } else play();
});
window.addEventListener('resize', fitFilenames);
document.querySelectorAll('[data-symbol]').forEach((element) => {
  element.innerHTML = symbol(element.dataset.symbol);
});
render();
