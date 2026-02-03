export interface Trade {
  id: string;
  user_id: string;
  habit_id: string | null;
  reward_id: string | null;
  amount: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface TradeInput {
  habit_id?: string | null;
  reward_id?: string | null;
  amount: number;
}
