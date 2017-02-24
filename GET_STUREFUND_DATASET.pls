create or replace procedure get_sturefund_dataset(p0 in varchar2 default null, p1 in varchar2 default null, ref_cur_out out SYS_REFCURSOR)
as
-- p0 : person Id
-- p1 : entry-date-limiter
-- ref_cur_out : out REF_CURSOR

v_sql varchar2(32000) := '';
v_sql_limiter varchar2(1000) := ' and trunc(tbraccd_entry_date) >= trunc(sysdate-1) ';
limiter_set boolean := FALSE;

begin

v_sql := 
'
SELECT DISTINCT
spriden_id student_id,
spriden_first_name||'' ''||spriden_last_name student_name,
spriden_first_name student_first_name,
spriden_last_name student_last_name,
goremal.GOREMAL_EMAIL_ADDRESS student_email_address,
''124 Raymond Ave'' student_street_line1,
''Poughkeepsie'' student_city,
''NY'' student_state,
''12604'' student_zip,
''USA'' student_country,
decode(sign(tbraccd_amount),-1,(trim(to_char(tbraccd_amount,''S999,999,999.99''))),trim(to_char(tbraccd_amount,''999,999,999.99''))) student_refund_amount,tbraccd_entry_date student_refund_entry_date
FROM spriden, tbraccd, goremal
WHERE
spriden_pidm = tbraccd_pidm
and spriden_pidm = goremal_pidm
and goremal_emal_code = ''VASR''
and spriden_change_ind is null
and tbraccd_detail_code = ''9812''
'
;

if p0 is not null then
  v_sql_limiter := ' and spriden_id = ''' || p0 || ''' ';
  v_sql := v_sql || v_sql_limiter;
  limiter_set := TRUE;
end if;

if limiter_set = FALSE then 
if p1 = 'yesterday' or p1 is null then
   v_sql := v_sql || v_sql_limiter;
   limiter_set := TRUE;
end if;

if limiter_set = FALSE then
begin
if p1 > 0 and p1 <= 90 then
  v_sql_limiter := ' and trunc(tbraccd_entry_date) >= trunc(sysdate-' || p1 || ')';
  v_sql := v_sql || v_sql_limiter;
end if;
exception
    when value_error then
         v_sql := v_sql || v_sql_limiter;
end;
end if;
end if;

  begin
    open ref_cur_out FOR
    v_sql;
  end;
  
end;