
create or replace function fa_convert_xp_to_sp(p_xp_balance integer, p_starting_sp integer, p_spent_sp integer)
returns integer language plpgsql immutable
set search_path = public
as $$
declare
  v_current_sp integer := p_starting_sp;
  v_remaining_xp integer := p_xp_balance;
  v_xp_converted_sp integer := 0;
  v_tier record;
  v_capacity_sp integer;
  v_affordable_sp integer;
  v_sp_this_tier integer;
begin
  for v_tier in
    select * from (values
      (40, 10),
      (80, 15),
      (150, 20),
      (200, 25),
      (2147483647, 30)
    ) as t(ceiling, rate)
  loop
    exit when v_remaining_xp <= 0;
    continue when v_current_sp >= v_tier.ceiling;
    v_capacity_sp := v_tier.ceiling - v_current_sp;
    v_affordable_sp := floor(v_remaining_xp::numeric / v_tier.rate)::integer;
    v_sp_this_tier := least(v_capacity_sp, v_affordable_sp);
    v_xp_converted_sp := v_xp_converted_sp + v_sp_this_tier;
    v_current_sp := v_current_sp + v_sp_this_tier;
    v_remaining_xp := v_remaining_xp - v_sp_this_tier * v_tier.rate;
  end loop;

  return p_starting_sp + v_xp_converted_sp;
end;
$$;
