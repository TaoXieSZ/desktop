import React, { useEffect, useMemo, useState } from 'react';

const DAEMON_BASE = import.meta.env.VITE_AHAKEY_DAEMON_URL ?? 'http://127.0.0.1:17342';
const TOKEN_STORAGE_KEY = 'ahakeyd-token';

type ShortcutAction = { type: 'shortcut'; hidCodes: number[] };
type RelayAction = { type: 'relay'; kind: 'fnGlobe' };
type KeyAction = ShortcutAction | RelayAction;

type ProfileKey = {
  index: number;
  label: string;
  action: KeyAction;
};

type ProfileMode = {
  id: number;
  label: string;
  keys: ProfileKey[];
};

type AhaKeyProfile = {
  schemaVersion: 1;
  id: string;
  name: string;
  modes: ProfileMode[];
};

type DaemonStatus = {
  ok: boolean;
  device?: { connected: boolean; status: string; blocker?: string };
  relay?: { ready: boolean; kind: string; blockers: string[] };
  approvalRelay?: { ready: boolean; state: string; lastAction: string; blockers: string[] };
  error?: string;
};

type ApplyResult = {
  ok: boolean;
  dryRun?: boolean;
  hardwareMutated?: boolean;
  commands?: Array<{ step: string; label: string; hex: string; hardwareMutating: boolean }>;
  blockers?: Array<{ kind: string; reason: string }>;
  hardwareResults?: Array<Record<string, unknown>>;
  error?: string;
};

const shortcutOptions = [
  { label: 'Enter', hidCodes: [0x28] },
  { label: 'Escape', hidCodes: [0x29] },
  { label: 'Tab', hidCodes: [0x2b] },
  { label: 'Space', hidCodes: [0x2c] },
  { label: 'Right Command', hidCodes: [0xe7] },
  { label: 'F17', hidCodes: [0x6c] },
  { label: 'F18', hidCodes: [0x6d] },
  { label: 'F19', hidCodes: [0x6e] },
  { label: 'F20', hidCodes: [0x6f] },
];

const modeLabels = ['默认层', 'AI 助手层', '工具层'];

function defaultProfile(): AhaKeyProfile {
  return {
    schemaVersion: 1,
    id: 'default',
    name: 'Default',
    modes: [0, 1, 2].map((mode) => ({
      id: mode,
      label: modeLabels[mode],
      keys: [0, 1, 2, 3].map((index) => {
        const defaults: Array<{ label: string; action: KeyAction }> = [
          { label: 'Doubao Fn', action: { type: 'shortcut', hidCodes: [0xe7] } },
          { label: 'Approve / Bypass', action: { type: 'shortcut', hidCodes: [0x6e] } },
          { label: 'Deny', action: { type: 'shortcut', hidCodes: [0x6f] } },
          { label: 'Enter', action: { type: 'shortcut', hidCodes: [0x28] } },
        ];
        return { index, ...defaults[index] };
      }),
    })),
  };
}

function App() {
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_STORAGE_KEY) ?? import.meta.env.VITE_AHAKEYD_TOKEN ?? '');
  const [profile, setProfile] = useState<AhaKeyProfile>(() => defaultProfile());
  const [modeId, setModeId] = useState(0);
  const [keyIndex, setKeyIndex] = useState(0);
  const [status, setStatus] = useState<DaemonStatus | null>(null);
  const [statusError, setStatusError] = useState('');
  const [result, setResult] = useState<ApplyResult | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [isApplying, setIsApplying] = useState(false);
  const [isWriting, setIsWriting] = useState(false);

  const selectedMode = useMemo(
    () => profile.modes.find((mode) => mode.id === modeId) ?? profile.modes[0],
    [profile, modeId],
  );
  const selectedKey = useMemo(
    () => selectedMode.keys.find((key) => key.index === keyIndex) ?? selectedMode.keys[0],
    [selectedMode, keyIndex],
  );
  const validationErrors = useMemo(() => validateProfile(profile), [profile]);

  useEffect(() => {
    localStorage.setItem(TOKEN_STORAGE_KEY, token);
  }, [token]);

  useEffect(() => {
    let cancelled = false;
    async function refresh() {
      try {
        const body = await request<DaemonStatus>('/api/status');
        if (!cancelled) {
          setStatus(body);
          setStatusError(body.ok ? '' : body.error ?? 'daemon status failed');
        }
      } catch (error) {
        if (!cancelled) {
          setStatus(null);
          setStatusError(error instanceof Error ? error.message : String(error));
        }
      }
    }
    refresh();
    const interval = window.setInterval(refresh, 2500);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [token]);

  function updateSelectedKey(next: Partial<ProfileKey>) {
    setProfile((current) => ({
      ...current,
      modes: current.modes.map((mode) => mode.id === modeId
        ? { ...mode, keys: mode.keys.map((key) => key.index === keyIndex ? { ...key, ...next } : key) }
        : mode),
    }));
  }

  async function saveProfile() {
    setIsSaving(true);
    setResult(null);
    try {
      const body = await request<{ ok: boolean; error?: string }>(`/api/profiles/${profile.id}`, {
        method: 'PUT',
        body: JSON.stringify(profile),
      });
      setResult(body.ok ? { ok: true, commands: [], dryRun: true } : { ok: false, error: body.error });
    } catch (error) {
      setResult({ ok: false, error: error instanceof Error ? error.message : String(error) });
    } finally {
      setIsSaving(false);
    }
  }

  async function applyDryRun() {
    setIsApplying(true);
    setResult(null);
    try {
      const body = await request<ApplyResult>('/api/apply', {
        method: 'POST',
        body: JSON.stringify({ dryRun: true, profile }),
      });
      setResult(body);
    } catch (error) {
      setResult({ ok: false, error: error instanceof Error ? error.message : String(error) });
    } finally {
      setIsApplying(false);
    }
  }

  async function writeHardware() {
    setIsWriting(true);
    setResult(null);
    try {
      const body = await request<ApplyResult>('/api/apply', {
        method: 'POST',
        body: JSON.stringify({ dryRun: false, profile }),
      });
      setResult(body);
    } catch (error) {
      setResult({ ok: false, error: error instanceof Error ? error.message : String(error) });
    } finally {
      setIsWriting(false);
    }
  }

  async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await fetch(`${DAEMON_BASE}${path}`, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        'X-AhaKey-Token': token,
        ...(init.headers ?? {}),
      },
    });
    return response.json() as Promise<T>;
  }

  return (
    <main className="shell">
      <section className="workspace" aria-label="AhaKey profile editor">
        <header className="topbar">
          <div>
            <p className="eyebrow">AhaKey Web Studio</p>
            <h1>Profile 控制台</h1>
          </div>
          <div className="statusPills" aria-label="daemon status">
            <span><i className={status?.ok ? 'dot green' : 'dot red'} />daemon {status?.ok ? 'online' : 'offline'}</span>
            <span><i className={status?.relay?.ready ? 'dot green' : 'dot red'} />Fn relay {status?.relay?.ready ? 'ready' : 'blocked'}</span>
            <span><i className={status?.approvalRelay?.ready ? 'dot green' : 'dot red'} />approve {status?.approvalRelay?.state ?? 'unknown'}</span>
            <span><i className="dot blue" />{DAEMON_BASE.replace('http://', '')}</span>
          </div>
        </header>

        <div className="profileToolbar">
          <label>
            Profile ID
            <input value={profile.id} onChange={(event) => setProfile({ ...profile, id: event.target.value })} />
          </label>
          <label>
            Name
            <input value={profile.name} onChange={(event) => setProfile({ ...profile, name: event.target.value })} />
          </label>
          <label>
            Token
            <input value={token} onChange={(event) => setToken(event.target.value)} />
          </label>
        </div>

        <div className="modeDock" role="tablist" aria-label="keyboard modes">
          {profile.modes.map((mode) => (
            <button
              key={mode.id}
              className={mode.id === modeId ? 'modeButton active' : 'modeButton'}
              onClick={() => setModeId(mode.id)}
              role="tab"
              aria-selected={mode.id === modeId}
            >
              <strong>{mode.label}</strong>
              <span>Mode {mode.id}</span>
            </button>
          ))}
        </div>

        <section className="deviceStage">
          <div className="keyboardBody">
            <div className="oledWindow" aria-label="selection preview">
              <div className="oledHud">
                <span>{profile.name}</span>
                <span>{selectedMode.label} / 按键 {selectedKey.index + 1}</span>
                <span>{selectedKey.label} · {actionLabel(selectedKey.action)}</span>
              </div>
            </div>

            <div className="keyTray">
              {selectedMode.keys.map((key) => (
                <button
                  className={key.index === keyIndex ? 'keyCap active' : 'keyCap'}
                  key={key.index}
                  onClick={() => setKeyIndex(key.index)}
                  aria-pressed={key.index === keyIndex}
                >
                  <strong>按键 {key.index + 1}</strong>
                  <span>{key.label}</span>
                  <small>{actionLabel(key.action)}</small>
                </button>
              ))}
            </div>
          </div>
        </section>
      </section>

      <aside className="panel" aria-label="profile controls">
        <section className="configStack">
          <div className="panelHeader">
            <span className="badge">Profile v{profile.schemaVersion}</span>
            <h2>{selectedMode.label} / 按键 {selectedKey.index + 1}</h2>
            <p>{statusError || status?.device?.blocker || '编辑会先 dry-run，不直接写硬件。'}</p>
          </div>

          <label className="fieldGroup">
            屏幕标签
            <input value={selectedKey.label} onChange={(event) => updateSelectedKey({ label: event.target.value })} />
          </label>

          <label className="fieldGroup">
            动作类型
            <select
              value={selectedKey.action.type}
              onChange={(event) => updateSelectedKey({
                action: event.target.value === 'relay'
                  ? { type: 'relay', kind: 'fnGlobe' }
                  : { type: 'shortcut', hidCodes: [0x28] },
              })}
            >
              <option value="shortcut">Shortcut</option>
              <option value="relay">Fn/Globe relay</option>
            </select>
          </label>

          {selectedKey.action.type === 'shortcut' ? (
            <label className="fieldGroup">
              快捷键
              <select
                value={selectedKey.action.hidCodes.join(',')}
                onChange={(event) => {
                  const next = shortcutOptions.find((item) => item.hidCodes.join(',') === event.target.value) ?? shortcutOptions[0];
                  updateSelectedKey({ action: { type: 'shortcut', hidCodes: next.hidCodes } });
                }}
              >
                {shortcutOptions.map((item) => (
                  <option key={item.label} value={item.hidCodes.join(',')}>{item.label}</option>
                ))}
              </select>
            </label>
          ) : (
            <div className="noticeBox">Fn/Globe 由 native daemon 中继，不作为普通 HID 写入固件。</div>
          )}

          {validationErrors.length > 0 && (
            <div className="errorBox">
              {validationErrors.map((item) => <span key={item}>{item}</span>)}
            </div>
          )}

          <div className="buttonRow">
            <button className="secondaryButton" disabled={isApplying || isWriting || validationErrors.length > 0} onClick={applyDryRun}>
              {isApplying ? '预览中...' : 'Dry-run 预览'}
            </button>
            <button className="primaryButton" disabled={isSaving || isWriting || validationErrors.length > 0} onClick={saveProfile}>
              {isSaving ? '保存中...' : '保存 Profile'}
            </button>
            <button className="writeButton" disabled={isWriting || isApplying || validationErrors.length > 0} onClick={writeHardware}>
              {isWriting ? '写入中...' : '写入小键盘'}
            </button>
          </div>

          {result && (
            <div className={result.ok ? 'resultBox success' : 'resultBox error'}>
              <strong>{result.ok ? 'OK' : 'Error'}</strong>
              {result.error && <span>{result.error}</span>}
              {typeof result.hardwareMutated === 'boolean' && <span>hardwareMutated: {String(result.hardwareMutated)}</span>}
              {result.blockers?.map((item) => <span key={`${item.kind}-${item.reason}`}>{item.kind}: {item.reason}</span>)}
              {result.commands?.slice(0, 8).map((command) => (
                <span key={`${command.step}-${command.hex}`}>{command.step}: {command.hex || command.label}</span>
              ))}
            </div>
          )}
        </section>
      </aside>
    </main>
  );
}

function actionLabel(action: KeyAction): string {
  if (action.type === 'relay') return 'Fn/Globe';
  const known = shortcutOptions.find((item) => item.hidCodes.join(',') === action.hidCodes.join(','));
  return known?.label ?? action.hidCodes.map((code) => `0x${code.toString(16)}`).join(' + ');
}

function validateProfile(profile: AhaKeyProfile): string[] {
  const errors: string[] = [];
  if (!profile.id.trim()) errors.push('Profile ID 不能为空');
  if (!profile.name.trim()) errors.push('Name 不能为空');
  for (const mode of profile.modes) {
    if (mode.id < 0 || mode.id > 2) errors.push(`Mode ${mode.id} 超出范围`);
    const seen = new Set<number>();
    for (const key of mode.keys) {
      if (seen.has(key.index)) errors.push(`Mode ${mode.id} 有重复按键 ${key.index + 1}`);
      seen.add(key.index);
      if (key.index < 0 || key.index > 3) errors.push(`按键 ${key.index + 1} 超出范围`);
      if (!key.label.trim()) errors.push(`Mode ${mode.id} 按键 ${key.index + 1} 缺少标签`);
      if (key.action.type === 'shortcut' && key.action.hidCodes.some((code) => code < 0 || code > 255)) {
        errors.push(`Mode ${mode.id} 按键 ${key.index + 1} HID code 无效`);
      }
    }
  }
  return errors;
}

export default App;
