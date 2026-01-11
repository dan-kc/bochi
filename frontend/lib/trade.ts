export interface Trade {
  id: string;
  user_id: string;
  task_id: string | null;
  reward_id: string | null;
  amount: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface TradeInput {
  task_id?: string | null;
  reward_id?: string | null;
  amount: number;
}
