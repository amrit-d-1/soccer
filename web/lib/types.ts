// Shared types mirroring the backend contract (tables, RPCs, views).

export type Role = 'player' | 'organizer';
export type RsvpStatus = 'in' | 'out' | 'maybe';
export type GameStatus =
  | 'scheduled'
  | 'played'
  | 'cancelled'
  | 'completed'
  | string;

export type Player = {
  id: string;
  name: string;
  phone: string | null;
  user_id: string | null;
  role: Role;
  is_active: boolean;
  sms_opt_out: boolean;
  created_at: string;
};

export type Game = {
  id: string;
  starts_at: string;
  location: string | null;
  capacity: number | null;
  status: GameStatus;
  notes: string | null;
  rsvp_close_at: string | null;
  ratings_close_at: string | null;
  created_at: string;
};

export type Rsvp = {
  id: string;
  game_id: string;
  player_id: string;
  status: RsvpStatus;
  responded_at: string | null;
};

export type Rating = {
  id: string;
  game_id: string;
  rater_id: string;
  overall: number;
  speed: number | null;
  intensity: number | null;
  comment: string | null;
  created_at: string;
};

// rpc game_roster(p_game_id) row shape.
export type RosterRow = {
  player_id: string;
  name: string;
  rsvp_status: RsvpStatus | null;
  played: boolean;
};

export type SmsKind = 'invite' | 'reminder' | 'rate_request';
