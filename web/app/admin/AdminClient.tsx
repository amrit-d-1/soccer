'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import {
  formatGameShortDate,
  formatGameTime,
  toDatetimeLocal,
  fromDatetimeLocal,
  normalizePhone,
  stat,
} from '@/lib/format';
import type { Game, Player, RosterRow, SmsKind } from '@/lib/types';

type GameSummary = {
  id: string;
  starts_at?: string;
  played_at?: string;
  location?: string | null;
  headcount?: number | null;
  response_rate?: number | null;
  mean_overall?: number | null;
  is_low_response?: boolean | null;
};

export function AdminClient({
  games,
  summaries,
  players,
  appearanceCounts,
}: {
  games: Game[];
  summaries: GameSummary[];
  players: Player[];
  appearanceCounts: Record<string, number>;
}) {
  const summaryById = useMemo(() => {
    const m = new Map<string, GameSummary>();
    summaries.forEach((s) => m.set(s.id, s));
    return m;
  }, [summaries]);

  return (
    <div className="stack" style={{ gap: 22 }}>
      <div className="stack" style={{ gap: 2 }}>
        <p className="eyebrow">Organizer</p>
        <h1 className="page-title">Admin</h1>
      </div>

      <GameEditor />

      <section className="stack" style={{ gap: 10 }}>
        <p className="section-label">Games</p>
        {games.length === 0 && (
          <div className="card">
            <p className="subtitle">No games yet. Create one above.</p>
          </div>
        )}
        {games.map((g) => (
          <GameAdminCard
            key={g.id}
            game={g}
            summary={summaryById.get(g.id)}
            players={players}
          />
        ))}
      </section>

      <RosterManager players={players} counts={appearanceCounts} />
    </div>
  );
}

/* ---------------- Game create / edit ---------------- */
function GameEditor({ game }: { game?: Game }) {
  const router = useRouter();
  const editing = !!game;
  const [open, setOpen] = useState(false);
  const [startsAt, setStartsAt] = useState(
    game ? toDatetimeLocal(game.starts_at) : ''
  );
  const [location, setLocation] = useState(game?.location ?? '');
  const [capacity, setCapacity] = useState(
    game?.capacity != null ? String(game.capacity) : ''
  );
  const [notes, setNotes] = useState(game?.notes ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    const iso = fromDatetimeLocal(startsAt);
    if (!iso) {
      setError('Pick a date and time.');
      return;
    }
    setBusy(true);
    const supabase = createClient();
    const payload = {
      starts_at: iso,
      location: location.trim() || null,
      capacity: capacity ? Number(capacity) : null,
      notes: notes.trim() || null,
    };
    const { error: err } = editing
      ? await supabase.from('game').update(payload).eq('id', game!.id)
      : await supabase
          .from('game')
          .insert({ ...payload, status: 'scheduled' });
    setBusy(false);
    if (err) {
      setError(err.message || 'Could not save the game.');
      return;
    }
    if (!editing) {
      setStartsAt('');
      setLocation('');
      setCapacity('');
      setNotes('');
      setOpen(false);
    } else {
      setOpen(false);
    }
    router.refresh();
  }

  if (editing && !open) {
    return (
      <button className="btn secondary small" onClick={() => setOpen(true)}>
        Edit game
      </button>
    );
  }

  if (!editing && !open) {
    return (
      <button className="btn" onClick={() => setOpen(true)}>
        + New game
      </button>
    );
  }

  return (
    <form onSubmit={save} className="card stack" style={{ gap: 12 }}>
      <p className="section-label">{editing ? 'Edit game' : 'New game'}</p>
      <div className="field">
        <label>Date &amp; time</label>
        <input
          className="input"
          type="datetime-local"
          value={startsAt}
          onChange={(e) => setStartsAt(e.target.value)}
        />
      </div>
      <div className="field">
        <label>Location</label>
        <input
          className="input"
          type="text"
          placeholder="e.g. Riverside Turf"
          value={location}
          onChange={(e) => setLocation(e.target.value)}
        />
      </div>
      <div className="field">
        <label>Capacity</label>
        <input
          className="input"
          type="number"
          inputMode="numeric"
          placeholder="e.g. 16"
          value={capacity}
          onChange={(e) => setCapacity(e.target.value)}
        />
      </div>
      <div className="field">
        <label>Notes</label>
        <textarea
          rows={2}
          placeholder="Anything players should know"
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
        />
      </div>
      <div className="btn-row">
        <button className="btn" disabled={busy}>
          {busy ? 'Saving…' : editing ? 'Save changes' : 'Create game'}
        </button>
        <button
          type="button"
          className="btn secondary"
          onClick={() => setOpen(false)}
        >
          Cancel
        </button>
      </div>
      {error && <p className="error">{error}</p>}
    </form>
  );
}

/* ---------------- Per-game admin card ---------------- */
function GameAdminCard({
  game,
  summary,
  players,
}: {
  game: Game;
  summary?: GameSummary;
  players: Player[];
}) {
  const [msg, setMsg] = useState('');
  const [sending, setSending] = useState<SmsKind | null>(null);
  const [showAttendance, setShowAttendance] = useState(false);

  async function sendSms(kind: SmsKind) {
    setMsg('');
    setSending(kind);
    const supabase = createClient();
    const { error } = await supabase.functions.invoke('send-game-sms', {
      body: { game_id: game.id, kind },
    });
    setSending(null);
    setMsg(error ? `Could not send ${kind}.` : `Sent ${kind.replace('_', ' ')}.`);
  }

  async function copyLinks(kind: 'game' | 'rate') {
    const supabase = createClient();
    const { data } = await supabase.rpc('game_roster', { p_game_id: game.id });
    const roster = (data as RosterRow[] | null) ?? [];
    const base = window.location.origin;
    const rows =
      roster.length > 0
        ? roster.map((r) => `${r.name}: ${base}/${kind}/${game.id}`)
        : [`${base}/${kind}/${game.id}`];
    const text = rows.join('\n');
    try {
      await navigator.clipboard.writeText(text);
      setMsg('Links copied to clipboard.');
    } catch {
      setMsg('Copy failed — long-press to copy manually.');
    }
  }

  const headcount = summary?.headcount ?? null;
  const responseRate = summary?.response_rate ?? null;
  const lowResponse = summary?.is_low_response ?? false;

  return (
    <div className="card stack" style={{ gap: 12 }}>
      <div className="row">
        <div className="stack" style={{ gap: 2 }}>
          <span style={{ fontWeight: 700 }}>
            {formatGameShortDate(game.starts_at)} ·{' '}
            {formatGameTime(game.starts_at)}
          </span>
          <span className="subtitle">{game.location ?? 'Pickup game'}</span>
        </div>
        <span className="badge">{game.status}</span>
      </div>

      <div className="stat-grid">
        <div className="stat-tile">
          <div className="stat-big" style={{ fontSize: 22 }}>
            {headcount ?? '—'}
          </div>
          <div className="n">played</div>
        </div>
        <div className="stat-tile">
          <div className="stat-big" style={{ fontSize: 22 }}>
            {stat(summary?.mean_overall)}
          </div>
          <div className="n">mean overall</div>
        </div>
        <div className="stat-tile">
          <div className="stat-big" style={{ fontSize: 22 }}>
            {responseRate != null ? `${Math.round(responseRate * 100)}%` : '—'}
          </div>
          <div className="n">response</div>
        </div>
      </div>

      {lowResponse && <p className="badge warn">Low response</p>}

      <GameEditor game={game} />

      <div className="btn-row">
        <button
          className="btn secondary small"
          disabled={sending !== null}
          onClick={() => sendSms('invite')}
        >
          {sending === 'invite' ? '…' : 'Send invites'}
        </button>
        <button
          className="btn secondary small"
          disabled={sending !== null}
          onClick={() => sendSms('reminder')}
        >
          {sending === 'reminder' ? '…' : 'Send reminder'}
        </button>
        <button
          className="btn secondary small"
          disabled={sending !== null}
          onClick={() => sendSms('rate_request')}
        >
          {sending === 'rate_request' ? '…' : 'Send rate requests'}
        </button>
      </div>

      <div className="btn-row">
        <button className="btn secondary small" onClick={() => copyLinks('game')}>
          Copy game links
        </button>
        <button className="btn secondary small" onClick={() => copyLinks('rate')}>
          Copy rate links
        </button>
      </div>

      <button
        className="btn secondary small"
        onClick={() => setShowAttendance((v) => !v)}
      >
        {showAttendance ? 'Hide attendance' : 'Confirm attendance'}
      </button>

      {showAttendance && (
        <AttendanceConfirm gameId={game.id} players={players} />
      )}

      {msg && <p className="hint">{msg}</p>}
    </div>
  );
}

/* ---------------- Attendance confirm ---------------- */
function AttendanceConfirm({
  gameId,
  players,
}: {
  gameId: string;
  players: Player[];
}) {
  const [loading, setLoading] = useState(true);
  const [roster, setRoster] = useState<RosterRow[]>([]);
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [played, setPlayed] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  async function load() {
    setLoading(true);
    const supabase = createClient();
    const { data } = await supabase.rpc('game_roster', { p_game_id: gameId });
    const rows = (data as RosterRow[] | null) ?? [];
    setRoster(rows);
    const chk: Record<string, boolean> = {};
    const pl: Record<string, boolean> = {};
    rows.forEach((r) => {
      pl[r.player_id] = !!r.played;
      // Pre-check those who played already, or who RSVP'd in.
      chk[r.player_id] = !!r.played || r.rsvp_status === 'in';
    });
    setChecked(chk);
    setPlayed(pl);
    setLoading(false);
  }

  // Load once on first render.
  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function save() {
    setBusy(true);
    setMsg('');
    const supabase = createClient();
    const toAdd: string[] = [];
    const toRemove: string[] = [];
    roster.forEach((r) => {
      const isChecked = !!checked[r.player_id];
      const wasPlayed = !!played[r.player_id];
      if (isChecked && !wasPlayed) toAdd.push(r.player_id);
      if (!isChecked && wasPlayed) toRemove.push(r.player_id);
    });

    let ok = true;
    if (toAdd.length) {
      const { error } = await supabase
        .from('appearance')
        .insert(toAdd.map((pid) => ({ game_id: gameId, player_id: pid })));
      if (error) ok = false;
    }
    for (const pid of toRemove) {
      const { error } = await supabase
        .from('appearance')
        .delete()
        .eq('game_id', gameId)
        .eq('player_id', pid);
      if (error) ok = false;
    }
    setBusy(false);
    setMsg(ok ? 'Attendance saved.' : 'Some changes could not be saved.');
    if (ok) load();
  }

  if (loading) return <p className="hint">Loading roster…</p>;

  // Show roster rows; if roster is empty, fall back to full active player list.
  const rows: { player_id: string; name: string }[] =
    roster.length > 0
      ? roster.map((r) => ({ player_id: r.player_id, name: r.name }))
      : players
          .filter((p) => p.is_active)
          .map((p) => ({ player_id: p.id, name: p.name }));

  return (
    <div className="stack" style={{ gap: 6 }}>
      <p className="hint">
        Pre-checked from RSVP&apos;d &ldquo;in&rdquo;. Confirm who actually
        played, then save before sending rate requests.
      </p>
      <div>
        {rows.map((r) => (
          <label key={r.player_id} className="check-row">
            <input
              type="checkbox"
              checked={!!checked[r.player_id]}
              onChange={(e) =>
                setChecked((c) => ({ ...c, [r.player_id]: e.target.checked }))
              }
            />
            <span>{r.name}</span>
          </label>
        ))}
      </div>
      <button className="btn small" disabled={busy} onClick={save}>
        {busy ? 'Saving…' : 'Save attendance'}
      </button>
      {msg && <p className="hint">{msg}</p>}
    </div>
  );
}

/* ---------------- Roster manager ---------------- */
function RosterManager({
  players,
  counts,
}: {
  players: Player[];
  counts: Record<string, number>;
}) {
  const router = useRouter();
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function addPlayer(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    const trimmed = name.trim();
    const e164 = normalizePhone(phone);
    if (!trimmed || !e164) {
      setError('Enter a name and a valid phone number.');
      return;
    }
    setBusy(true);
    const supabase = createClient();
    const { error: err } = await supabase.from('player').insert({
      name: trimmed,
      phone: e164,
      role: 'player',
      is_active: true,
      sms_opt_out: false,
    });
    setBusy(false);
    if (err) {
      setError(err.message || 'Could not add player.');
      return;
    }
    setName('');
    setPhone('');
    router.refresh();
  }

  async function toggle(
    p: Player,
    field: 'is_active' | 'sms_opt_out',
    value: boolean
  ) {
    const supabase = createClient();
    await supabase.from('player').update({ [field]: value }).eq('id', p.id);
    router.refresh();
  }

  return (
    <section className="stack" style={{ gap: 10 }}>
      <p className="section-label">Roster</p>

      <form onSubmit={addPlayer} className="card stack" style={{ gap: 10 }}>
        <div className="field">
          <label>Add player — name</label>
          <input
            className="input"
            type="text"
            placeholder="Name"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Phone</label>
          <input
            className="input"
            type="tel"
            inputMode="tel"
            placeholder="(555) 123-4567"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
        </div>
        <button className="btn" disabled={busy}>
          {busy ? 'Adding…' : 'Add player'}
        </button>
        {error && <p className="error">{error}</p>}
      </form>

      <div className="card">
        {players.length === 0 ? (
          <p className="subtitle">No players yet.</p>
        ) : (
          <ul className="name-list">
            {players.map((p) => (
              <li key={p.id}>
                <div className="stack" style={{ gap: 2 }}>
                  <span style={{ fontWeight: 600 }}>
                    {p.name}
                    {p.role === 'organizer' && (
                      <span className="badge" style={{ marginLeft: 8 }}>
                        organizer
                      </span>
                    )}
                  </span>
                  <span className="hint">
                    {counts[p.id] ?? 0} games
                    {!p.is_active ? ' · inactive' : ''}
                    {p.sms_opt_out ? ' · opted out' : ''}
                  </span>
                </div>
                <div className="btn-row" style={{ gap: 6 }}>
                  <button
                    className="btn-link"
                    onClick={() => toggle(p, 'is_active', !p.is_active)}
                  >
                    {p.is_active ? 'Deactivate' : 'Activate'}
                  </button>
                  <button
                    className="btn-link"
                    onClick={() => toggle(p, 'sms_opt_out', !p.sms_opt_out)}
                  >
                    {p.sms_opt_out ? 'Opt in' : 'Opt out'}
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
