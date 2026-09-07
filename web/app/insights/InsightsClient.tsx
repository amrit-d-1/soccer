'use client';

import {
  BarChart,
  Bar,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
  Legend,
} from 'recharts';
import { formatGameShortDate, stat } from '@/lib/format';

const AMBER = '#c45621';
const INK_SOFT = '#6b5f57';

// Read the first present key from a row (view column names may vary slightly).
function pick<T = any>(row: any, keys: string[], fallback: T | null = null): T | null {
  for (const k of keys) {
    if (row && row[k] !== undefined && row[k] !== null) return row[k] as T;
  }
  return fallback;
}

const DOW_ORDER = [
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
];

function dowRank(label: string): number {
  const i = DOW_ORDER.indexOf(String(label).trim().toLowerCase());
  return i === -1 ? 99 : i;
}

export function InsightsClient({
  headcount,
  daytime,
  presence,
  trend,
  summary,
}: {
  headcount: any[];
  daytime: any[];
  presence: any[];
  trend: any[];
  summary: any[];
}) {
  // --- Header: mean speed / intensity across qualifying games ---
  const qualifying = summary.filter((s) => {
    const rr = pick<number>(s, ['response_rate']);
    return rr != null && rr >= 0.4;
  });
  const avg = (rows: any[], keys: string[]) => {
    const vals = rows
      .map((r) => pick<number>(r, keys))
      .filter((v): v is number => v != null && !isNaN(v));
    if (!vals.length) return null;
    return vals.reduce((a, b) => a + b, 0) / vals.length;
  };
  const meanSpeed = avg(qualifying, ['mean_speed']);
  const meanIntensity = avg(qualifying, ['mean_intensity']);

  // --- 1. Headcount effect ---
  const headcountData = [...headcount]
    .sort(
      (a, b) =>
        (pick<number>(a, ['bucket_order']) ?? 0) -
        (pick<number>(b, ['bucket_order']) ?? 0)
    )
    .map((r) => ({
      bucket: pick<string>(r, ['bucket'], '?')!,
      mean: Number(pick<number>(r, ['mean_rating', 'mean_overall', 'mean']) ?? 0),
      n: pick<number>(r, ['n_ratings', 'session_count', 'game_count', 'n']) ?? 0,
    }));

  // --- 2. Best day ---
  const daytimeData = [...daytime]
    .map((r) => ({
      day: String(
        pick<string>(r, ['dow_label', 'day', 'day_name', 'dow_name', 'label', 'dow']) ?? '?'
      ),
      mean: Number(pick<number>(r, ['mean_overall', 'mean_rating', 'mean']) ?? 0),
      n:
        pick<number>(r, ['n_ratings', 'session_count', 'game_count', 'n']) ?? 0,
    }))
    .sort((a, b) => dowRank(a.day) - dowRank(b.day))
    .map((d) => ({ ...d, day: d.day.slice(0, 3) }));

  // --- 3. Player presence ---
  const presenceRows = presence.map((r) => ({
    name: pick<string>(r, ['name'], '?')!,
    meanWith: pick<number>(r, ['mean_with']),
    meanWithout: pick<number>(r, ['mean_without']),
    adjusted: pick<number>(r, ['adjusted_with']),
    delta: pick<number>(r, ['delta_adjusted']),
    appearances: pick<number>(r, ['appearances', 'n_with']) ?? 0,
    enough: pick<boolean>(r, ['has_enough_data']) ?? false,
  }));
  const qualified = presenceRows
    .filter((r) => r.enough)
    .sort((a, b) => (b.delta ?? -99) - (a.delta ?? -99));
  const insufficient = presenceRows.filter((r) => !r.enough);

  // --- 4. Trend ---
  const trendData = [...trend]
    .map((r) => ({
      date: pick<string>(r, ['played_at', 'starts_at', 'date']),
      mean: pick<number>(r, ['mean_overall']),
      rolling: pick<number>(r, ['rolling_avg_4']),
      n: pick<number>(r, ['n_ratings', 'response_count']) ?? 0,
    }))
    .filter((r) => r.date)
    .sort(
      (a, b) => new Date(a.date!).getTime() - new Date(b.date!).getTime()
    )
    .map((r) => ({
      ...r,
      label: formatGameShortDate(r.date!),
    }));

  const noData = (n: number) =>
    n === 0 ? <p className="subtitle">Not enough data yet.</p> : null;

  return (
    <div className="stack" style={{ gap: 20 }}>
      <div className="stack" style={{ gap: 2 }}>
        <p className="eyebrow">Organizer</p>
        <h1 className="page-title">Insights</h1>
        <p className="hint">
          Mean speed{' '}
          <strong className="mono">{stat(meanSpeed)}</strong> · mean intensity{' '}
          <strong className="mono">{stat(meanIntensity)}</strong>{' '}
          <span className="muted">(across qualifying games)</span>
        </p>
        <p className="hint">
          Games under 40% response are excluded from these stats and flagged.
        </p>
      </div>

      {/* 1. Headcount effect */}
      <section className="card">
        <p className="section-label">Headcount effect</p>
        <p className="subtitle">Mean overall rating by turnout bucket.</p>
        {noData(headcountData.length) ?? (
          <>
            <div className="chart-wrap">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart
                  data={headcountData}
                  margin={{ top: 8, right: 8, left: -18, bottom: 0 }}
                >
                  <CartesianGrid stroke="#eee4d7" vertical={false} />
                  <XAxis
                    dataKey="bucket"
                    tick={{ fontSize: 12, fill: INK_SOFT }}
                  />
                  <YAxis domain={[0, 5]} tick={{ fontSize: 12, fill: INK_SOFT }} />
                  <Tooltip
                    formatter={(v: any) => stat(Number(v))}
                    labelFormatter={(l) => `Headcount ${l}`}
                  />
                  <Bar dataKey="mean" fill={AMBER} radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
            <p className="hint">
              n ={' '}
              {headcountData.map((d) => `${d.bucket}: ${d.n}`).join(' · ')}
            </p>
          </>
        )}
      </section>

      {/* 2. Best day */}
      <section className="card">
        <p className="section-label">Best day</p>
        <p className="subtitle">Mean overall rating by day of week.</p>
        {noData(daytimeData.length) ?? (
          <>
            <div className="chart-wrap">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart
                  data={daytimeData}
                  margin={{ top: 8, right: 8, left: -18, bottom: 0 }}
                >
                  <CartesianGrid stroke="#eee4d7" vertical={false} />
                  <XAxis dataKey="day" tick={{ fontSize: 12, fill: INK_SOFT }} />
                  <YAxis domain={[0, 5]} tick={{ fontSize: 12, fill: INK_SOFT }} />
                  <Tooltip formatter={(v: any) => stat(Number(v))} />
                  <Bar dataKey="mean" fill={AMBER} radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
            <p className="hint">
              n = {daytimeData.map((d) => `${d.day}: ${d.n}`).join(' · ')}
            </p>
          </>
        )}
      </section>

      {/* 3. Player presence */}
      <section className="card">
        <p className="section-label">Player presence</p>
        <p className="subtitle">
          Is the game rated better when a player shows up? Adjusted for sample
          size.
        </p>
        {presenceRows.length === 0 ? (
          <p className="subtitle">Not enough data yet.</p>
        ) : (
          <>
            {qualified.map((r) => (
              <div key={r.name} className="presence-item">
                <div className="stack" style={{ gap: 2 }}>
                  <span style={{ fontWeight: 600 }}>{r.name}</span>
                  <span className="hint">
                    with {stat(r.meanWith)} · without {stat(r.meanWithout)} · n=
                    {r.appearances}
                  </span>
                </div>
                <span
                  className={
                    (r.delta ?? 0) >= 0 ? 'delta-pos' : 'delta-neg'
                  }
                >
                  {(r.delta ?? 0) >= 0 ? '+' : ''}
                  {stat(r.delta, 2)}
                </span>
              </div>
            ))}
            {qualified.length === 0 && (
              <p className="subtitle">No players with enough data yet.</p>
            )}
            {insufficient.length > 0 && (
              <p className="hint" style={{ marginTop: 10 }}>
                Not enough data yet (&lt;6 games):{' '}
                {insufficient
                  .map((r) => `${r.name} (${r.appearances})`)
                  .join(', ')}
              </p>
            )}
          </>
        )}
      </section>

      {/* 4. Trend */}
      <section className="card">
        <p className="section-label">Trend over time</p>
        <p className="subtitle">
          Mean overall per game with a 4-game rolling average.
        </p>
        {noData(trendData.length) ?? (
          <div className="chart-wrap">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart
                data={trendData}
                margin={{ top: 8, right: 8, left: -18, bottom: 0 }}
              >
                <CartesianGrid stroke="#eee4d7" vertical={false} />
                <XAxis
                  dataKey="label"
                  tick={{ fontSize: 11, fill: INK_SOFT }}
                />
                <YAxis domain={[0, 5]} tick={{ fontSize: 12, fill: INK_SOFT }} />
                <Tooltip formatter={(v: any) => stat(Number(v))} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Line
                  type="monotone"
                  dataKey="mean"
                  name="Mean"
                  stroke={INK_SOFT}
                  strokeWidth={1.5}
                  dot={{ r: 2 }}
                />
                <Line
                  type="monotone"
                  dataKey="rolling"
                  name="Rolling avg (4)"
                  stroke={AMBER}
                  strokeWidth={2.5}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        )}
      </section>
    </div>
  );
}
